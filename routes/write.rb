class WriteRoute < BaseRoute
  post '/api/v2/write' do # rubocop:disable Metrics/BlockLength
    content_type 'application/json'

    settings.logger.info 'Received write request'

    influx_line = request.body.read
    settings.logger.info "Influx line: #{influx_line}"

    bucket = params['bucket']
    org = params['org']
    precision = params['precision'] || 'ns'
    influx_token = request.env['HTTP_AUTHORIZATION']&.sub(/^Token /, '')

    settings.logger.info "to #{bucket} in #{org} with precision #{precision}"

    unless influx_token
      settings.logger.error 'Missing InfluxDB token'
      halt 401, { error: 'Missing InfluxDB token' }.to_json
    end

    unless bucket
      settings.logger.error 'Missing bucket'
      halt 400, { error: 'Missing bucket' }.to_json
    end

    unless org
      settings.logger.error 'Missing org'
      halt 400, { error: 'Missing org' }.to_json
    end

    begin
      Processor.new(influx_token, bucket, org, precision).run(influx_line)
      status 204
    rescue InfluxDB2::InfluxError => e
      settings.logger.warn "#{e.class}: #{e.message}"
      settings.logger.debug e.backtrace.join("\n")
      halt 202, { error: e.message }.to_json
    rescue InvalidLineProtocolError => e
      settings.logger.error "#{e.class}: #{e.message}"
      settings.logger.debug e.backtrace.join("\n")
      halt 400, { error: e.message }.to_json
    rescue StandardError => e
      settings.logger.error "#{e.class}: #{e.message}"
      settings.logger.error e.backtrace.join("\n")
      halt 500, { error: e.message }.to_json
    end
  end
end
