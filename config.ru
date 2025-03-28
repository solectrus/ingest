require_relative 'lib/boot'

ActiveRecord::MigrationContext.new('db/migrate').up

ENV['APP_ENV'] ||= 'development'
if ENV['APP_ENV'] == 'development'
  logger = Logger.new($stdout)
  logger.level = Logger::DEBUG
  ActiveRecord::Base.logger = logger
end

puts 'SOLECTRUS :: Ingest'
puts "Forwarding to #{InfluxWriter::INFLUX_URL}"
puts "\n"

Thread.new { OutboxWorker.run_loop }
Thread.new { CleanupWorker.run_loop }

run App
