class StartupMessage
  def self.print!(io : IO = STDOUT)
    print_header(io)
    print_configured_sensors(io)
    print_house_power_destination(io)
    print_forwarding_info(io)
  end

  private def self.print_header(io : IO)
    io.puts "Ingest for SOLECTRUS, #{BuildInfo.to_s}"
    io.puts "https://github.com/solectrus/ingest"
    io.puts "Copyright (c) 2025 Georg Ledermann"
    io.puts

    io.puts "Compiled by Crystal #{Crystal::VERSION}"
    io.puts
  end

  private def self.print_configured_sensors(io : IO)
    io.puts "Configured sensors:"
    SensorEnvConfig.config.each do |sensor, value|
      excluded = SensorEnvConfig.exclude_from_house_power_keys.includes?(sensor)
      note = excluded ? " (excluded from house_power)" : ""

      output = sprintf(
        " %-25s → %s:%s%s",
        sensor,
        value.measurement,
        value.field,
        note
      )
      io.puts output
    end
    io.puts
  end

  private def self.print_house_power_destination(io : IO)
    if (calculated = SensorEnvConfig.house_power_calculated)
      formatted = sprintf(
        "Result of house_power calculation → %s:%s",
        calculated.measurement,
        calculated.field
      )
      io.puts formatted
    else
      io.puts "Calculated house_power will OVERRIDE the incoming value!"
    end
    io.puts
  end

  private def self.print_forwarding_info(io : IO)
    io.puts "Forwarding to #{influx_url}"
    io.puts
  end

  private def self.influx_url
    schema = ENV.fetch("INFLUX_SCHEMA", "http")
    host = ENV.fetch("INFLUX_HOST", "localhost")
    port = ENV.fetch("INFLUX_PORT", "8086")
    "#{schema}://#{host}:#{port}"
  end
end
