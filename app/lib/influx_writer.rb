class InfluxWriter
  INFLUX_HOST = ENV.fetch('INFLUX_HOST')
  INFLUX_PORT = ENV.fetch('INFLUX_PORT', '8086')
  INFLUX_SCHEMA = ENV.fetch('INFLUX_SCHEMA', 'http')

  INFLUX_URL = "#{INFLUX_SCHEMA}://#{INFLUX_HOST}:#{INFLUX_PORT}".freeze

  # Carries the HTTP status, because the caller has to tell the 4xx codes
  # apart: they differ in what InfluxDB did with the data.
  class ClientError < StandardError
    def initialize(message, code = nil)
      super(message)
      @code = code
    end

    attr_reader :code
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
      raise translate(e)
    end

    # Maps the answer of InfluxDB to what the caller has to do with the lines:
    # keep them for a retry (429 and 5xx), or deal with the refusal (other
    # 4xx).
    #
    # InfluxDB2::InfluxError#code is the HTTP status as a String (e.g. "400"),
    # so it must be coerced before comparing against numeric ranges.
    def translate(error)
      case error.code.to_i
      # The token is temporarily over its quota. The data is correct, so the
      # lines stay queued and the caller writes them again later.
      when 429
        ServerError.new("Over quota (#{error.code}): #{error.message}")
      when 400..499
        ClientError.new(
          "Client error (#{error.code}): #{error.message}",
          error.code.to_i,
        )
      when 500..599
        ServerError.new("Server error (#{error.code}): #{error.message}")
      else
        error
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
