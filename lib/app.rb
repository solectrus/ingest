class App < Sinatra::Base
  post '/api/v2/write' do
    content_type 'application/json'

    influx_line = request.body.read
    bucket = params['bucket']
    org = params['org']
    precision = params['precision']

    influx_token = request.env['HTTP_AUTHORIZATION']&.sub(/^Token /, '')
    halt 401, { error: 'Missing InfluxDB token' }.to_json unless influx_token
    halt 400, { error: 'Missing bucket' }.to_json unless bucket
    halt 400, { error: 'Missing org' }.to_json unless org

    begin
      LineProcessor.new(influx_token, bucket, org, precision).process(
        influx_line,
      )
      status 204
    rescue InvalidLineProtocolError
      status 400
    rescue StandardError => e
      warn "Processing error: #{e}"
      status 500
    end
  end

  get '/health' do
    'OK'
  end
end
