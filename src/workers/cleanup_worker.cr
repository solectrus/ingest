class CleanupWorker
  CLEANUP_INTERVAL = 1.hour
  RETENTION_HOURS  = 36.hours

  def self.run_loop
    loop do
      sleep CLEANUP_INTERVAL
      run
    end
  end

  def self.run
    Log.info { "[Cleanup] Deleting old entries..." }

    cutoff_time = (Time.utc - RETENTION_HOURS).to_s("%Y-%m-%d %H:%M:%S.%6N")

    deleted = Database.thread_safe_write do
      result = Database.pool.exec("DELETE FROM incomings WHERE created_at < ?", cutoff_time)
      result.rows_affected
    end

    Log.info { "[Cleanup] Deleted #{deleted} entries" }
  rescue ex
    Log.error { "[Cleanup] Error: #{ex.class} - #{ex.message}" }
    Log.error { ex.backtrace.join("\n") }
  end
end
