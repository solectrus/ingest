require_relative 'lib/boot'

ActiveRecord::MigrationContext.new('db/migrate').up

Thread.new do
  loop do
    sleep 3600

    puts '[Cleanup] Deleting old entries...'
    count = Sensor.cleanup
    puts "[Cleanup] Deleted #{count} entries"
  rescue StandardError => e
    warn "[Cleanup] Error: #{e.message}"
  end
end

ReplayWorker.new.replay!

run App
