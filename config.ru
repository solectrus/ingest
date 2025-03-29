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

puts 'Configured sensors:'
SensorEnvConfig.config.each do |sensor, value|
  excluded = SensorEnvConfig.exclude_from_house_power_keys.include?(sensor)
  note = (excluded ? ' (excluded from house_power)' : '')

  output =
    format(
      '  %<sensor>-25s → %<measurement>s:%<field>s%<note>s',
      sensor:,
      measurement: value[:measurement],
      field: value[:field],
      note:,
    )

  puts output
end

puts
if (calculated = SensorEnvConfig.house_power_calculated)
  puts "Result of house_power calculation → #{calculated[:measurement]}:#{calculated[:field]}"
else
  puts 'Calculated house_power OVERRIDES original!'
end

puts
puts "Forwarding to #{InfluxWriter::INFLUX_URL}"
puts

Thread.new { OutboxWorker.run_loop }
Thread.new { CleanupWorker.run_loop }

run App
