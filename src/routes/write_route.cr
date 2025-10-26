REGEX_TOKEN = /\AToken (.+)\z/

before_all "/api/v2/write" do |env|
  env.response.headers["X-Ingest-Version"] = BuildInfo.version
  env.response.headers["Date"] = Time.utc.to_s("%a, %d %b %Y %H:%M:%S GMT")
end

post "/api/v2/write" do |env|
  start_time = Time.monotonic

  env.response.content_type = "application/json"

  # Extract token
  auth_header = env.request.headers["Authorization"]?
  unless auth_header
    env.response.status_code = 401
    next({error: "Missing token"}.to_json)
  end

  influx_token = auth_header[REGEX_TOKEN, 1]?
  unless influx_token
    env.response.status_code = 401
    next({error: "Missing token"}.to_json)
  end

  # Extract bucket
  bucket = env.params.query["bucket"]?
  unless bucket && !bucket.empty?
    env.response.status_code = 400
    next({error: "Missing bucket"}.to_json)
  end

  # Extract org
  org = env.params.query["org"]?
  unless org && !org.empty?
    env.response.status_code = 400
    next({error: "Missing org"}.to_json)
  end

  # Extract precision
  precision = env.params.query["precision"]? || "ns"

  # Read body
  raw_body = env.request.body.try(&.gets_to_end) || ""
  body = EncodingHelper.clean_utf8(raw_body)
  lines = body.strip.lines.map(&.chomp)

  if lines.empty?
    env.response.status_code = 204
    next
  end

  begin
    Processor.new(
      influx_token: influx_token,
      bucket: bucket,
      org: org,
      precision: precision
    ).run(lines)

    # Track stats
    duration_ms = (Time.monotonic - start_time).total_milliseconds.round(2)
    Stats.inc(:http_requests)
    Stats.add(:http_duration_total, duration_ms)
    Stats.inc(:"http_response_204")

    env.response.status_code = 204
  rescue ex : InvalidLineProtocolError
    Log.error { "#{ex}: #{ex.message}" }
    Log.error { ex.backtrace.join("\n") }

    duration_ms = (Time.monotonic - start_time).total_milliseconds.round(2)
    Stats.inc(:http_requests)
    Stats.add(:http_duration_total, duration_ms)
    Stats.inc(:"http_response_400")

    env.response.status_code = 400
    {error: ex.message}.to_json
  rescue ex
    Log.error { "#{ex}: #{ex.message}" }
    Log.error { ex.backtrace.join("\n") }

    duration_ms = (Time.monotonic - start_time).total_milliseconds.round(2)
    Stats.inc(:http_requests)
    Stats.add(:http_duration_total, duration_ms)
    Stats.inc(:"http_response_500")

    env.response.status_code = 500
    {error: ex.message}.to_json
  end
end
