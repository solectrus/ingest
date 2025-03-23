require 'house_power_formula'
require 'line_protocol_parser'
require 'sensor_env_config'
require 'sensor_data_store'

class HousePowerCalculator
  SENSOR_STORE = SensorDataStore.new
  SENSOR_CONFIG = SensorEnvConfig.load
  HOUSE_POWER_SENSOR = SensorEnvConfig.house_power_sensor

  class << self
    def process_lines(lines)
      lines.map { |line| process_line(line) }
    end

    private

    def process_line(line)
      parsed = LineProtocolParser.parse(line)
      return line unless parsed

      # Store all numeric fields
      parsed.fields.each do |field, value|
        SENSOR_STORE.store(measurement: parsed.measurement, field:, timestamp: parsed.timestamp, value:) if numeric?(value)
      end

      if house_power_trigger?(parsed)
        corrected = calculate_house_power(parsed.timestamp)
        if corrected
          parsed.fields = { HOUSE_POWER_SENSOR[:field] => corrected }
          return LineProtocolParser.build(parsed)
        end
      end

      line
    end

    def house_power_trigger?(parsed)
      return false unless HOUSE_POWER_SENSOR

      parsed.measurement == HOUSE_POWER_SENSOR[:measurement] &&
        parsed.fields.key?(HOUSE_POWER_SENSOR[:field])
    end

    def calculate_house_power(target_ts)
      powers = SENSOR_CONFIG.transform_values do |config|
        SENSOR_STORE.interpolate(measurement: config[:measurement], field: config[:field], target_ts:)
      end
      HousePowerFormula.calculate(**powers)
    end

    def numeric?(val)
      val.is_a?(Integer) || val.is_a?(Float)
    end
  end
end
