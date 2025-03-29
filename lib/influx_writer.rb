class InfluxWriter
  INFLUX_HOST = ENV.fetch('INFLUX_HOST')
  INFLUX_PORT = ENV.fetch('INFLUX_PORT', '8086')
  INFLUX_SCHEMA = ENV.fetch('INFLUX_SCHEMA', 'http')

  INFLUX_URL = "#{INFLUX_SCHEMA}://#{INFLUX_HOST}:#{INFLUX_PORT}".freeze

  class ClientError < StandardError
  end

  class ServerError < StandardError
  end

  @clients = {} # token => InfluxDB2::Client
  @write_apis = {} # token => WriteApi
  @mutex = Mutex.new

  class << self
    def write(lines, influx_token:, bucket:, org:, precision:)
      payload = lines.is_a?(Array) ? lines.join("\n") : lines
      write_api_for(influx_token).write(
        bucket:,
        org:,
        precision:,
        data: payload,
      )
    rescue InfluxDB2::InfluxError => e
      case e.code
      when 400..499
        raise ClientError, "Client error (#{e.code}): #{e.message}"
      when 500..599
        raise ServerError, "Server error (#{e.code}): #{e.message}"
      else
        raise
      end
    end

    def close_all
      @mutex.synchronize do
        @write_apis.clear
        @clients.each_value(&:close!)
        @clients.clear
      end
    end

    private

    def write_api_for(token)
      @mutex.synchronize do
        @write_apis[token] ||= client_for(token).create_write_api
      end
    end

    def client_for(token)
      @clients[token] ||= InfluxDB2::Client.new(
        INFLUX_URL,
        token,
        use_ssl: INFLUX_URL.start_with?('https'),
      )
    end
  end
end

at_exit { InfluxWriter.close_all }
