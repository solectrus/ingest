class OutboxWorker
  BATCH_SIZE = 500

  record Key, target_id : Int64, timestamp : Int64

  def self.run_loop
    loop do
      run_once
      OutboxNotifier.wait
    rescue ex
      Log.error { "[OutboxWorker] Error: #{ex.class} - #{ex.message}" }
      Log.error { ex.backtrace.join("\n") }
      sleep 1.second
    end
  end

  def self.run_once : Int32
    total_processed = 0

    # Fetch batches
    Database.pool.query("SELECT * FROM outgoings ORDER BY id LIMIT ?", BATCH_SIZE) do |rs|
      outgoings = [] of {Int64, Int64, String} # id, target_id, line_protocol

      rs.each do
        id = rs.read(Int64)
        target_id = rs.read(Int64)
        line_protocol = rs.read(String)
        created_at = rs.read(String)

        outgoings << {id, target_id, line_protocol}
      end

      # Group by target_id and timestamp
      groups = outgoings.group_by do |id, target_id, line_protocol|
        Key.new(target_id, extract_timestamp(line_protocol))
      end

      groups.each do |key, group|
        ids = group.map { |id, _, _| id }
        target_id = group.first[1]
        line_protocols = group.map { |_, _, lp| lp }

        # Load target
        target = Target.find(target_id)
        next unless target

        # Try to write
        result = write_batch(line_protocols, target, ids)
        if result
          # Delete successful outgoings
          Database.thread_safe_write do
            placeholders = ids.map { "?" }.join(",")
            Database.pool.exec("DELETE FROM outgoings WHERE id IN (#{placeholders})", args: ids.map(&.as(DB::Any)))
          end

          total_processed += ids.size
        end
      end
    end

    total_processed
  end

  private def self.extract_timestamp(line : String) : Int64
    line.split.last.to_i64
  rescue
    0_i64
  end

  private def self.write_batch(lines : Array(String), target : Target, ids : Array(Int64)) : Bool
    InfluxWriter.write(
      lines,
      influx_token: target.influx_token,
      bucket: target.bucket,
      org: target.org,
      precision: target.precision
    )

    true
  rescue ex : InfluxWriter::ClientError
    Log.warn { "[OutboxWorker] Permanent write failure (deleted): #{ex.message}" }

    # Delete permanently failed outgoings
    Database.thread_safe_write do
      placeholders = ids.map { "?" }.join(",")
      Database.pool.exec("DELETE FROM outgoings WHERE id IN (#{placeholders})", args: ids.map(&.as(DB::Any)))
    end

    false
  rescue ex : InfluxWriter::ServerError | Socket::Error | IO::TimeoutError
    Log.warn { "[OutboxWorker] Temporary write failure (will retry): #{ex.class} - #{ex.message}" }
    false
  end
end
