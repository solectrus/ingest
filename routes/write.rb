class WriteRoute < Sinatra::Base
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
      warn "#{e}, #{e.backtrace.join("\n")}"
      status 202
    rescue InvalidLineProtocolError => e
      warn "#{e}, #{e.backtrace.join("\n")}"
      status 400
    rescue StandardError => e
      warn "#{e}, #{e.backtrace.join("\n")}"
      status 500
    end
  end
end
