class WriteRoute < BaseRoute
  REGEX_TOKEN = /\AToken (.+)\z/

  # An upper bound for the body of one gzipped request, and the size in which
  # it is inflated.
  #
  # Compression hides how much memory a request costs. Line protocol carries
  # the same keys on every line, so it compresses about 12 times, and 200 KB of
  # zeros expand to 200 MB (measured factor: 1029). Without a limit, one small
  # request thus allocates more than the container has, and five Puma threads
  # do it at the same time.
  #
  # 8 MB holds about 100_000 lines of line protocol. The largest batch a
  # collector sends after an outage is around 5000 lines, so the limit is 20
  # times what the data needs.
  MAX_UNZIPPED_BYTES = 8 * 1024 * 1024
  UNZIP_CHUNK_BYTES = 64 * 1024

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

    body = EncodingHelper.clean_utf8(read_body)
    lines = body.strip.lines

    halt 204 if lines.empty?

    precision =
      params['precision'].presence || InfluxDB2::WritePrecision::NANOSECOND

    begin
      Processor.new(influx_token:, bucket:, org:, precision:).run(lines)
      halt 204
    rescue LineProtocolParser::InvalidLineProtocolError => e
      handle(e, 400)
    rescue StandardError => e
      handle(e, 500)
    end
  end

  private

  # Sinatra reads the parameters before it calls this route. Rack parses a
  # body of type application/x-www-form-urlencoded into those parameters, and
  # that read empties the stream: the route then found no line, stored
  # nothing and still answered 204 No Content. The rewind puts the line
  # protocol back, whatever type the client sent it under.
  def read_body
    request.body.rewind
    body = request.body.read

    gzip? && body.present? ? gunzip(body) : body
  end

  # The InfluxDB client for JavaScript compresses every body above 1000 bytes,
  # so an ioBroker adapter or a Node collector sends gzip as soon as it batches
  # a few sensors. Without this step the compressed bytes reach the parser, no
  # line of the request parses, and the client reads 400 for data that is
  # correct.
  def gzip?
    request.env['HTTP_CONTENT_ENCODING'].to_s.split(',').any? { it.strip.casecmp?('gzip') }
  end

  # Inflated in chunks, so an oversized body stops at the limit instead of
  # reaching memory in full first.
  def gunzip(body)
    reader = Zlib::GzipReader.new(StringIO.new(body))
    result = +''

    while (chunk = reader.read(UNZIP_CHUNK_BYTES))
      result << chunk
      too_large! if result.bytesize > MAX_UNZIPPED_BYTES
    end

    result
  rescue Zlib::Error => e
    halt 400, { error: "Invalid gzip body: #{e.message}" }.to_json
  ensure
    reader&.close
  end

  def too_large!
    halt 413,
         {
           error:
             "Body exceeds #{MAX_UNZIPPED_BYTES} bytes when unzipped",
         }.to_json
  end

  def handle(exception, status)
    warn "#{exception}: #{exception.message}"
    warn exception.backtrace.join("\n")

    halt status, { error: exception.message }.to_json
  end
end
