require 'influxdb-client'

class InfluxWriter
  INFLUX_URL = ENV.fetch('INFLUX_URL', 'http://localhost:8086')

  class << self
    def forward_influx_line(
      influx_line,
      influx_token:,
      bucket:,
      org:,
      precision:
    )
      client =
        InfluxDB2::Client.new(
          INFLUX_URL,
          influx_token,
          use_ssl: INFLUX_URL.start_with?('https'),
        )
      client.create_write_api.write(
        data: influx_line,
        bucket:,
        org:,
        precision:,
      )
      client.close!
    end
  end
end
