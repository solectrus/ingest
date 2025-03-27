class WriteRoute < Sinatra::Base
  post '/api/v2/write' do # rubocop:disable Metrics/BlockLength
    content_type 'application/json'

    influx_line = request.body.read
    bucket = params['bucket']
    org = params['org']
    precision = params['precision'] || 'ns'
    influx_token = request.env['HTTP_AUTHORIZATION']&.sub(/^Token /, '')

    unless influx_token
      puts 'Missing InfluxDB token'
      halt 401, { error: 'Missing InfluxDB token' }.to_json
    end

    unless bucket
      puts 'Missing bucket'
      halt 400, { error: 'Missing bucket' }.to_json
    end

    unless org
      puts 'Missing org'
      halt 400, { error: 'Missing org' }.to_json
    end

    begin
      Processor.new(influx_token, bucket, org, precision).run(influx_line)
      status 204
    rescue InfluxDB2::InfluxError => e
      puts "#{e.class}: #{e.message}"
      puts e.backtrace.join("\n")
      halt 202, { error: e.message }.to_json
    rescue InvalidLineProtocolError => e
      puts "#{e.class}: #{e.message}"
      puts e.backtrace.join("\n")
      halt 400, { error: e.message }.to_json
    rescue StandardError => e
      puts "#{e.class}: #{e.message}"
      puts e.backtrace.join("\n")
      halt 500, { error: e.message }.to_json
    end
  end
end
