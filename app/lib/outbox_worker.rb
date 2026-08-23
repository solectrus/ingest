class OutboxWorker
  BATCH_SIZE = 500

  def self.run_loop
    loop do
      run_once
      OutboxNotifier.wait
    rescue StandardError => e
      warn "[OutboxWorker] Error: #{e.class} - #{e.message}"
      warn e.backtrace.join("\n")
      sleep 1
    end
  end

  # Queued lines go to InfluxDB in batches of one target. Line protocol carries
  # the timestamp per line, so lines of different timestamps share one request.
  #
  # The queue was grouped by timestamp too before. A backlog holds one
  # timestamp per collector poll, so that made one HTTP request per poll: 1,228
  # requests for 16,794 rows instead of 20. The client opens a new connection
  # for each of them.
  def self.run_once
    total_processed = 0

    # InfluxDB is unreachable for this target. Every further batch of it runs
    # into the same timeout, so the pass skips them and picks them up on the
    # next signal.
    unreachable = Set.new

    Outgoing.includes(:target).find_in_batches(batch_size: BATCH_SIZE) do |batch|
      batch.group_by(&:target).each do |target, outgoings|
        next if unreachable.include?(target.id)

        case write_batch(outgoings, target)
        when :written
          delete(outgoings)
          total_processed += outgoings.size
        when :retry
          unreachable << target.id
        end
      end
    end

    total_processed
  end

  def self.delete(outgoings)
    Database.thread_safe_write do
      Outgoing.where(id: outgoings.map(&:id)).delete_all
    end
  end

  def self.write_batch(outgoings, target)
    lines = outgoings.map(&:line_protocol)

    InfluxWriter.write(
      lines,
      influx_token: target.influx_token,
      bucket: target.bucket,
      org: target.org,
      precision: target.precision,
    )

    :written
  rescue InfluxWriter::ClientError => e
    warn "[OutboxWorker] Permanent write failure (deleted): #{e.message}"
    delete(outgoings)
    :dropped
  rescue InfluxWriter::ServerError,
         SocketError,
         Timeout::Error,
         Errno::ECONNREFUSED => e
    warn "[OutboxWorker] Temporary write failure (will retry): #{e.class} - #{e.message}"
    :retry
  end
end
