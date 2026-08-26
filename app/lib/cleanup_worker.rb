class CleanupWorker
  CLEANUP_INTERVAL = 1.hour
  RETENTION = ENV.fetch('RETENTION_HOURS', '12').to_i.hours

  # The cleanup runs first, then it sleeps. A restart thus deletes at once what
  # a former run left behind. If the worker slept first, every restart would
  # delay the cleanup by a full interval, and a service that restarts often
  # would never delete a row.
  def self.run_loop
    loop do
      run
      sleep CLEANUP_INTERVAL
    end
  end

  def self.run
    puts '[Cleanup] Deleting old entries...'

    deleted =
      Database.thread_safe_write do
        count = Incoming.where(created_at: ..RETENTION.ago).delete_all

        # Reclaims the space of the deleted rows, a few megabytes per run. The
        # vacuum writes, so it takes the same lock as every other writer.
        Database.incremental_vacuum!

        count
      end

    puts "[Cleanup] Deleted #{deleted} entries"
  rescue StandardError => e
    warn "[Cleanup] Error: #{e.class} - #{e.message}"
    warn e.backtrace.join("\n")
  end
end
