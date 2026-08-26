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
    # keep them for a retry (429, 5xx and every network failure), or deal with
    # the refusal (other 4xx).
    #
    # Every branch returns a ClientError or a ServerError, so the caller needs
    # to know these two classes alone. It returned the InfluxError itself
    # before, and the caller does not rescue that class: a stopped InfluxDB
    # thus escaped the whole delivery path, see below.
    #
    # InfluxDB2::InfluxError#code is the HTTP status as a String (e.g. "400"),
    # so it must be coerced before comparing against numeric ranges.
    def translate(error)
      # The client wraps a network failure into an InfluxError that carries no
      # status, and puts the cause into #original. A refused connection, a
      # reset one, a closed one and a timeout all arrive this way, so none of
      # them ever reached the caller as the Errno or the Timeout::Error it
      # started as.
      #
      # The lines are correct, InfluxDB just did not answer, so they stay
      # queued.
      return ServerError.new("Network error: #{error.message}") if error.original

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
        # An InfluxError with no status and no cause. Nothing here says that
        # the lines are wrong, so the caller keeps them instead of dropping
        # them.
        ServerError.new("Unknown error: #{error.message}")
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
