require 'sensor_env_config'
require 'sensor_data_store'
require 'influx_writer'
require 'house_power_formula'
require 'line_protocol_parser'

class HousePowerService
  SENSOR_STORE = SensorDataStore.new

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

    # Store all numeric fields into SQLite
    parsed.fields.each do |field, value|
      if numeric?(value)
        SENSOR_STORE.store(
          measurement: parsed.measurement,
          field:,
          timestamp: parsed.timestamp,
          value:,
        )
      end
    end

    # Check if this line is the house_power sensor trigger
    if house_power_trigger?(parsed)
      corrected = calculate_house_power(parsed.timestamp)
      if corrected
        parsed.fields[SensorEnvConfig.house_power[:field]] = corrected
        return write_influx(LineProtocolParser.build(parsed))
      end
    end

    # Otherwise, forward unmodified
    write_influx(LineProtocolParser.build(parsed))
  end

  def house_power_trigger?(parsed)
    house_sensor = SensorEnvConfig.house_power
    parsed.measurement == house_sensor[:measurement] &&
      parsed.fields.key?(house_sensor[:field])
  end

  def calculate_house_power(target_ts)
    powers =
      SensorEnvConfig::SENSOR_KEYS
        .reject { _1 == :house_power }
        .to_h do |sensor_key|
          config = SensorEnvConfig.send(sensor_key)
          value =
            SENSOR_STORE.interpolate(
              measurement: config[:measurement],
              field: config[:field],
              target_ts:,
            )
          [sensor_key, value]
        end

    HousePowerFormula.calculate(**powers)
  end

  def write_influx(line)
    InfluxWriter.forward_influx_line(
      line,
      influx_token: @influx_token,
      bucket: @bucket,
      org: @org,
      precision: @precision,
    )
  end

  def numeric?(val)
    val.is_a?(Integer) || val.is_a?(Float)
  end
end
