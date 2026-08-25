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

        if (handled = deliver(outgoings, target))
          total_processed += handled
        else
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

  # Sends one batch and clears it from the queue. Returns how many lines
  # reached InfluxDB, or nil if InfluxDB could not be reached. A line that
  # InfluxDB refuses is dropped and does not count.
  def self.deliver(outgoings, target)
    write(outgoings, target)
    delete(outgoings)
    outgoings.size
  rescue InfluxWriter::ClientError => e
    reject(outgoings, target, e)
  rescue InfluxWriter::ServerError,
         SocketError,
         Timeout::Error,
         Errno::ECONNREFUSED => e
    Stats.inc(:outgoing_failures)
    warn "[OutboxWorker] Temporary write failure (will retry): #{e.class} - #{e.message}"
    nil
  end

  # A batch holds up to 500 lines since the outbox stopped grouping by
  # timestamp. Splitting it finds the lines InfluxDB refuses and keeps the
  # rest, but it only helps for the codes that leave the good lines unwritten.
  def self.reject(outgoings, target, error)
    return drop(outgoings, error) unless splittable?(outgoings, error)

    half = outgoings.size / 2

    # If InfluxDB is gone, the rest waits for the next pass instead of running
    # into one timeout per half.
    return unless (first = deliver(outgoings[0...half], target))
    return unless (second = deliver(outgoings[half..], target))

    first + second
  end

  # InfluxDB writes no point of a request it cannot parse (400) or cannot
  # accept for its size (413), so a smaller batch can still get through.
  #
  # The other codes need no split. For 422 the documentation says "data that
  # has not been rejected is ingested and queryable", so the good lines are
  # already stored. A 401 or 403 refuses the batch whatever its size: splitting
  # a batch of 500 lines under a wrong token sent 999 requests.
  SPLIT_ON = [400, 413].freeze

  def self.splittable?(outgoings, error)
    SPLIT_ON.include?(error.code) && !outgoings.one?
  end

  # A 422 is not a loss: InfluxDB stored every line it could and named the
  # rest. Reporting those lines as dropped would send a reader looking for
  # data that is there.
  PARTIAL_WRITE = 422

  # The log holds the reason, but only the counters reach the statistics page.
  # A wrong token drops every line of a batch, and the page showed nothing of
  # it before.
  def self.drop(outgoings, error)
    if error.code == PARTIAL_WRITE
      Stats.inc(:outgoing_partial, outgoings.size)
      warn "[OutboxWorker] InfluxDB rejected points of #{outgoings.size} lines, " \
           "it stored the rest: #{error.message}"
    else
      Stats.inc(:outgoing_dropped, outgoings.size)
      warn "[OutboxWorker] Permanent write failure (dropped #{outgoings.size}): #{error.message}"
    end

    delete(outgoings)
    0
  end

  def self.write(outgoings, target)
    InfluxWriter.write(
      outgoings.map(&:line_protocol),
      influx_token: target.influx_token,
      bucket: target.bucket,
      org: target.org,
      precision: target.precision,
    )
  end
end
