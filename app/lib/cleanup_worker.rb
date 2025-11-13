class CleanupWorker
  CLEANUP_INTERVAL = 1.hour
  RETENTION = ENV.fetch('RETENTION_HOURS', '12').to_i.hours

  def self.run_loop
    loop do
      sleep CLEANUP_INTERVAL
      run
    end
  end

  def self.run
    puts '[Cleanup] Deleting old entries...'

    deleted =
      Database.thread_safe_write do
        Incoming.where(created_at: ..RETENTION.ago).delete_all
      end

    puts "[Cleanup] Deleted #{deleted} entries"
  rescue StandardError => e
    warn "[Cleanup] Error: #{e.class} - #{e.message}"
    warn e.backtrace.join("\n")
  end
end
