class InfluxWriter
  INFLUX_HOST = ENV.fetch('INFLUX_HOST')
  INFLUX_PORT = ENV.fetch('INFLUX_PORT', '8086')
  INFLUX_SCHEMA = ENV.fetch('INFLUX_SCHEMA', 'http')

  INFLUX_URL = "#{INFLUX_SCHEMA}://#{INFLUX_HOST}:#{INFLUX_PORT}".freeze

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
