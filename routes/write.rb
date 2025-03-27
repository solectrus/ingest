class WriteRoute < BaseRoute
  post '/api/v2/write' do
    content_type 'application/json'

    influx_line = request.body.read
    bucket = params['bucket']
    org = params['org']
    precision = params['precision'] || 'ns'
    influx_token = request.env['HTTP_AUTHORIZATION']&.sub(/^Token /, '')

    halt 401, { error: 'Missing InfluxDB token' }.to_json unless influx_token
    halt 400, { error: 'Missing bucket' }.to_json unless bucket
    halt 400, { error: 'Missing org' }.to_json unless org

    begin
      Processor.new(influx_token, bucket, org, precision).run(influx_line)
      status 204
    rescue InfluxDB2::InfluxError => e
      halt 202, { error: e.message }.to_json
    rescue InvalidLineProtocolError => e
      halt 400, { error: e.message }.to_json
    rescue StandardError => e
      halt 500, { error: e.message }.to_json
    end
  end
end
