require 'dotenv/load'
require 'sinatra/base'
require 'json'

require 'influx_writer'
require 'sensor_data_store'
require 'house_power_service'

class App < Sinatra::Base
  post '/api/v2/write' do
    influx_line = request.body.read
    bucket = params['bucket']
    org = params['org']
    precision = params['precision']

    influx_token = request.env['HTTP_AUTHORIZATION']&.sub(/^Token /, '')
    halt 401, 'Missing InfluxDB token' unless influx_token
    halt 400, 'Missing bucket' unless bucket
    halt 400, 'Missing org' unless org

    begin
      HousePowerService.new(influx_token, bucket, org, precision).process(influx_line)
      status 204
    rescue StandardError => e
      warn "Processing error: #{e}"
      status 500
    end
  end

  get '/health' do
    'OK'
  end
end
