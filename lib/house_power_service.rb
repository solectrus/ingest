require_relative 'sqlite'
require_relative 'influx_writer'
require_relative 'house_power_formula'
require_relative 'line_protocol_parser'
require_relative 'sensor_env_config'

class HousePowerService
  SENSOR_STORE = SensorDataStore.new
  SENSOR_CONFIG = SensorEnvConfig.load

  def initialize(influx_token, bucket, org, precision)
    @influx_token = influx_token
    @bucket = bucket
    @org = org
    @precision = precision
  end

  def process(influx_line)
    lines = influx_line.split("\n")
    lines.each { |line| process_and_store(line) }
  end

  private

  def process_and_store(line)
    parsed = LineProtocolParser.parse(line)
    return unless parsed

    parsed.fields.each do |field, value|
      next unless numeric?(value)

      SENSOR_STORE.store(
        measurement: parsed.measurement,
        field:,
        timestamp: parsed.timestamp,
        value:,
      )
    end

    if parsed.fields.key?('house_power')
      corrected = calculate_house_power(parsed.timestamp)
      if corrected
        parsed.fields['house_power'] = corrected
        InfluxWriter.forward_influx_line(
          LineProtocolParser.build(parsed),
          influx_token: @influx_token,
          bucket: @bucket,
          org: @org,
          precision: @precision,
        )
        return
      end
    end

    InfluxWriter.forward_influx_line(
      LineProtocolParser.build(parsed),
      influx_token: @influx_token,
      bucket: @bucket,
      org: @org,
      precision: @precision,
    )
  end

  def calculate_house_power(target_ts)
    powers =
      SENSOR_CONFIG.transform_values do |config|
        SENSOR_STORE.interpolate(
          measurement: config[:measurement],
          field: config[:field],
          target_ts:,
        )
      end

    HousePowerFormula.calculate(**powers)
  end

  def numeric?(val)
    val.is_a?(Integer) || val.is_a?(Float)
  end
end
