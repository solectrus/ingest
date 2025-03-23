require 'dotenv/load'
require 'sinatra/base'
require 'json'

require_relative 'influx_writer'
require_relative 'buffer'
require_relative 'house_power_calculator'

class App < Sinatra::Base
  post '/api/v2/write' do
    handle_write_request
  end

  get '/health' do
    handle_health_request
  end

  get '/stats' do
    content_type :html
    cache = HousePowerCalculator.cache_stats
    <<~HTML
      <html>
        <head><title>Ingest Stats</title></head>
        <body>
          <h1>Ingest Stats</h1>
          <p><strong>Buffered Entries:</strong> #{Buffer.size}</p>
          <p><strong>Last Replay Success:</strong> #{Buffer.last_replay_success?}</p>
          <p><strong>Last House Power:</strong> #{HousePowerCalculator.last_house_power || 'n/a'}</p>
          <h2>StateCache</h2>
          <p><strong>Cached Keys (#{cache[:size]}):</strong></p>
          <ul>
            #{cache[:keys].map { |k| "<li>#{k}</li>" }.join}
          </ul>
        </body>
      </html>
    HTML
  end

  private

  def handle_write_request
    influx_token = fetch_token
    bucket = params['bucket']
    org = params['org']
    precision = params['precision']

    halt 401, 'Missing InfluxDB token' unless influx_token
    halt 400, 'Missing bucket' unless bucket
    halt 400, 'Missing org' unless org

    process_and_forward(influx_token, bucket, org, precision)
  end

  def handle_health_request
    'OK'
  end

  def fetch_token
    request.env['HTTP_AUTHORIZATION']&.sub(/^Token /, '')
  end

  def process_and_forward(influx_token, bucket, org, precision)
    influx_line = request.body.read
    lines = influx_line.split("\n")
    lines = HousePowerCalculator.process_lines(lines)
    processed_line_protocol = lines.join("\n")

    begin
      InfluxWriter.forward_influx_line(
        processed_line_protocol,
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
      Buffer.add({ influx_line: processed_line_protocol, influx_token:, bucket:, org:, precision: })
      status 202 # Accepted
    end
  end
end
