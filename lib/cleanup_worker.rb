class CleanupWorker
  CLEANUP_INTERVAL = 1.hour
  RETENTION_HOURS = 12.hours

  def self.run_loop
    loop do
      sleep CLEANUP_INTERVAL
      run
    end
  end

  def self.run
    puts '[Cleanup] Deleting old entries...'
    deleted = Incoming.cleanup(cutoff: RETENTION_HOURS.ago)

    puts "[Cleanup] Deleted #{deleted} entries"
  rescue StandardError => e
    warn "[Cleanup] Error: #{e.message}"
  end
end
