class WriteRoute < BaseRoute
  REGEX_TOKEN = /\AToken (.+)\z/

  post '/api/v2/write' do
    content_type 'application/json'

    headers 'X-Ingest-Version' => BuildInfo.version, 'Date' => Time.now.httpdate

    influx_token = request.env['HTTP_AUTHORIZATION'].to_s[REGEX_TOKEN, 1]
    halt 401, { error: 'Missing token' }.to_json unless influx_token

    bucket = params['bucket'].presence
    halt 400, { error: 'Missing bucket' }.to_json unless bucket

    org = params['org'].presence
    halt 400, { error: 'Missing org' }.to_json unless org

    lines = request.body.read.strip.lines
    halt 204 if lines.empty?

    precision =
      params['precision'].presence || InfluxDB2::WritePrecision::NANOSECOND

    begin
      Processor.new(influx_token:, bucket:, org:, precision:).run(lines)
      status 204
    rescue InvalidLineProtocolError => e
      handle(e, 400)
    rescue StandardError => e
      handle(e, 500)
    end
  end

  private

  def handle(exception, status)
    warn "#{exception}: #{exception.message}"
    warn exception.backtrace.join("\n")

    halt status, { error: exception.message }.to_json
  end
end
