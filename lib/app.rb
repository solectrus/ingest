require 'dotenv/load'
require 'sinatra/base'
require 'json'

require 'influx_writer'
require 'sensor_data_store'
require 'house_power_service'
require 'sensor_env_config'

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
      HousePowerService.new(influx_token, bucket, org, precision).process(influx_line)
      status 204
    rescue StandardError => e
      warn "Processing error: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
      status 500
    end
  end

  get '/health' do
    'OK'
  end
end
