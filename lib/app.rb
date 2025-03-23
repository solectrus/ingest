require 'dotenv/load'
require 'sinatra/base'
require 'json'

require_relative 'influx_writer'
require_relative 'sqlite'
require_relative 'house_power_service'

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
      puts "Error: #{e}"
      Buffer.add({ influx_line:, influx_token:, bucket:, org:, precision: })
      status 202
    end
  end

  get '/health' do
    'OK'
  end
end
