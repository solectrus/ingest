class StartupMessage
  def self.print!
    print_header
    print_configured_sensors
    print_house_power_destination
    print_forwarding_info
    print_retention_info
  end

  def self.print_header
    puts "Ingest for SOLECTRUS, #{BuildInfo}"

    puts 'https://github.com/solectrus/ingest'
    puts 'Copyright (c) 2025 Georg Ledermann'
    puts
    puts "Using Ruby #{RUBY_VERSION} on platform #{RUBY_PLATFORM}"
    puts
  end

  def self.print_configured_sensors
    puts 'Configured sensors:'
    SensorEnvConfig.config.each do |sensor, value|
      excluded = SensorEnvConfig.exclude_from_house_power_keys.include?(sensor)
      note = (excluded ? ' (excluded from house_power)' : '')

      output =
        format(
          '  %<sensor>-25s → %<measurement>s:%<field>s%<note>s',
          sensor: sensor,
          measurement: value[:measurement],
          field: value[:field],
          note: note,
        )
      puts output
    end
    puts
  end

  def self.print_house_power_destination
    if (calculated = SensorEnvConfig.house_power_calculated)
      formatted =
        format(
          'Result of house_power calculation → %<measurement>s:%<field>s',
          measurement: calculated[:measurement],
          field: calculated[:field],
        )

      puts formatted
    else
      puts 'Calculated house_power will OVERRIDE the incoming value!'
    end
    puts
  end

  def self.print_forwarding_info
    puts "Forwarding to #{InfluxWriter::INFLUX_URL}"
    puts
  end

  def self.print_retention_info
    retention_hours = CleanupWorker::RETENTION.in_hours.to_i
    puts "SQLite retention: #{retention_hours} hours"
    puts
  end
end
