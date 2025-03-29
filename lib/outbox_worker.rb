class OutboxWorker
  INTERVAL = 2.seconds
  BATCH_SIZE = 500

  def self.run_loop
    loop do
      processed = run_once
      sleep(processed.zero? ? INTERVAL : 0)
    end
  end

  def self.run_once
    total_processed = 0

    Outgoing
      .includes(:target)
      .find_in_batches(batch_size: BATCH_SIZE) do |batch|
        batch
          .group_by { |o| [o.target_id, extract_timestamp(o.line_protocol)] }
          .each_value do |outgoings|
            target = outgoings.first.target
            next unless write_batch(outgoings, target)

            Database.thread_safe_write do
              Outgoing.where(id: outgoings).delete_all
            end
            total_processed += outgoings.size
          end
      end

    total_processed
  end

  def self.extract_timestamp(line)
    line.split.last.to_i
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

    true
  rescue InfluxWriter::ClientError => e
    warn "[OutboxWorker] Permanent write failure (deleted): #{e.message}"
    Database.thread_safe_write { Outgoing.where(id: outgoings).delete_all }
    false
  rescue InfluxWriter::ServerError,
         SocketError,
         Timeout::Error,
         Errno::ECONNREFUSED => e
    warn "[OutboxWorker] Temporary write failure (will retry): #{e.class} - #{e.message}"
    false
  end
end
