require_relative 'lib/boot'

Thread.new do
  loop do
    sleep 3600

    puts '[Cleanup] Deleting old entries'
    STORE.cleanup(cutoff)
  rescue StandardError => e
    warn "[Cleanup] Error: #{e.message}"
  end
end

ReplayWorker.new.replay!

run App
