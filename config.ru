require_relative 'lib/boot'

ActiveRecord::MigrationContext.new('db/migrate').up

ENV['APP_ENV'] ||= 'development'
if ENV['APP_ENV'] == 'development'
  logger = Logger.new($stdout)
  logger.level = Logger::DEBUG
  ActiveRecord::Base.logger = logger
end

puts 'Ingest for SOLECTRUS'
puts "Version #{ENV.fetch('VERSION', '<unknown>')} " \
       "(#{ENV.fetch('REVISION', '<unknown>')}), " \
       "built at #{ENV.fetch('BUILDTIME', '<unknown>')}"
puts 'https://github.com/solectrus/ingest'
puts 'Copyright (c) 2025 Georg Ledermann'
puts
puts 'Sensors for calculating house_power:'
SensorEnvConfig.config.each do |sensor, value|
  next if sensor == :house_power

  excluded = SensorEnvConfig.exclude_from_house_power_keys.include?(sensor)
  puts "  #{sensor}: #{value[:measurement]}:#{value[:field]}#{excluded ? ' (excluded from house_power)' : nil}"
end
puts "Forwarding to #{InfluxWriter::INFLUX_URL}"
puts

Thread.new { OutboxWorker.run_loop }
Thread.new { CleanupWorker.run_loop }

run App
