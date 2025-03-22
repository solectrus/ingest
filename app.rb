require 'sinatra/base'
require 'json'

require_relative 'influx_writer'
require_relative 'buffer'

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
      InfluxWriter.forward_influx_line(
        influx_line,
        influx_token:,
        bucket:,
        org:,
        precision:,
      )
      status 204 # No content
    rescue InfluxDB2::InfluxError => e
      halt 400, e.message # Bad request
    rescue SocketError, Timeout::Error, Errno::ECONNREFUSED, OpenSSL::SSL::SSLError => e
      puts e
      Buffer.add({ influx_line:, influx_token:, bucket:, org:, precision: })
      status 202 # Accepted
    end
  end

  get '/health' do
    'OK'
  end
end
