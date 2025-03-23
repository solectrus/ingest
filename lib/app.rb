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
      status 204 # No Content
    rescue InfluxDB2::InfluxError => e
      warn e
      status 202 # Accepted
    rescue InvalidLineProtocolError
      warn e
      status 400 # Bad Request
    rescue StandardError => e
      warn e
      status 500 # Internal Server Error
    end
  end

  get '/health' do
    'OK'
  end
end
