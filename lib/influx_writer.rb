class InfluxWriter
  INFLUX_HOST = ENV.fetch('INFLUX_HOST')
  INFLUX_PORT = ENV.fetch('INFLUX_PORT', '8086')
  INFLUX_SCHEMA = ENV.fetch('INFLUX_SCHEMA', 'http')

  INFLUX_URL = "#{INFLUX_SCHEMA}://#{INFLUX_HOST}:#{INFLUX_PORT}".freeze

  class ClientError < StandardError
  end

  class ServerError < StandardError
  end

  class << self
    def write(lines, influx_token:, bucket:, org:, precision:)
      client =
        InfluxDB2::Client.new(
          INFLUX_URL,
          influx_token,
          use_ssl: INFLUX_URL.start_with?('https'),
        )

      payload = lines.is_a?(Array) ? lines.join("\n") : lines

      client.create_write_api.write(data: payload, bucket:, org:, precision:)
    rescue InfluxDB2::InfluxError => e
      case e.code
      when 400..499
        raise ClientError, "Client error (#{e.code}): #{e.message}"
      when 500..599
        raise ServerError, "Server error (#{e.code}): #{e.message}"
      else
        raise
      end
    ensure
      client&.close!
    end
  end
end
