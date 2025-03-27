require_relative 'lib/boot'

ActiveRecord::MigrationContext.new('db/migrate').up

puts 'SOLECTRUS :: Ingest'
puts "Forwarding to #{InfluxWriter::INFLUX_URL}"
puts "\n"

Thread.new { OutboxWorker.run_loop }
Thread.new { CleanupWorker.run_loop }

run App
