class WriteRoute < BaseRoute
  REGEX_TOKEN = /\AToken (.+)\z/

  before do
    @start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  after do
    next unless @track_http_stats

    duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - @start_time) * 1000).round(2)

    Stats.inc(:http_requests)
    Stats.add(:http_duration_total, duration_ms)
    Stats.inc(:"http_response_#{response.status}")
  end

  post '/api/v2/write' do
    @track_http_stats = true

    content_type 'application/json'

    headers 'X-Ingest-Version' => BuildInfo.version, 'Date' => Time.now.httpdate

    influx_token = request.env['HTTP_AUTHORIZATION'].to_s[REGEX_TOKEN, 1]
    halt 401, { error: 'Missing token' }.to_json unless influx_token

    bucket = params['bucket'].presence
    halt 400, { error: 'Missing bucket' }.to_json unless bucket

    org = params['org'].presence
    halt 400, { error: 'Missing org' }.to_json unless org

    raw_body = request.body.read
    body = EncodingHelper.clean_utf8(raw_body)
    lines = body.strip.lines

    halt 204 if lines.empty?

    precision =
      params['precision'].presence || InfluxDB2::WritePrecision::NANOSECOND

    begin
      Processor.new(influx_token:, bucket:, org:, precision:).run(lines)
      halt 204
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
