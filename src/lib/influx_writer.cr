require "http/client"

class InfluxWriter
  class ClientError < Exception
  end

  class ServerError < Exception
  end

  INFLUX_HOST   = ENV.fetch("INFLUX_HOST", "influxdb")
  INFLUX_PORT   = ENV.fetch("INFLUX_PORT", "8086").to_i
  INFLUX_SCHEMA = ENV.fetch("INFLUX_SCHEMA", "http")

  INFLUX_URL = "#{INFLUX_SCHEMA}://#{INFLUX_HOST}:#{INFLUX_PORT}"

  def self.write(lines : Array(String) | String, influx_token : String, bucket : String, org : String, precision : String)
    payload = lines.is_a?(Array) ? lines.join("\n") : lines

    uri = URI.parse("#{INFLUX_URL}/api/v2/write")
    uri.query = HTTP::Params.encode({
      "bucket"    => bucket,
      "org"       => org,
      "precision" => precision,
    })

    headers = HTTP::Headers{
      "Authorization" => "Token #{influx_token}",
      "Content-Type"  => "text/plain; charset=utf-8",
    }

    response = HTTP::Client.post(uri, headers: headers, body: payload)

    case response.status_code
    when 200..299
      # Success
    when 400..499
      raise ClientError.new("Client error (#{response.status_code}): #{response.body}")
    when 500..599
      raise ServerError.new("Server error (#{response.status_code}): #{response.body}")
    else
      raise Exception.new("Unexpected response code: #{response.status_code}")
    end
  end
end
