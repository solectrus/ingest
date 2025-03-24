class InfluxWriter
  INFLUX_URL = ENV.fetch('INFLUX_URL', 'http://localhost:8086')

  class << self
    # Supports single line (String) or multiple lines (Array of Strings)
    def write(lines, influx_token:, bucket:, org:, precision:)
      client =
        InfluxDB2::Client.new(
          INFLUX_URL,
          influx_token,
          use_ssl: INFLUX_URL.start_with?('https'),
        )

      payload = lines.is_a?(Array) ? lines.join("\n") : lines

      client.create_write_api.write(data: payload, bucket:, org:, precision:)
    ensure
      client&.close!
    end
  end
end
