require_relative 'house_power_formula'
require_relative 'line_protocol_parser'
require_relative 'state_cache'

class HousePowerCalculator
  @cache = StateCache.new
  @last_house_power = nil

  class << self
    attr_reader :last_house_power

    def process_lines(lines)
      lines.filter_map { |line| process_line(line) }
    end

    def cache_stats
      @cache.stats
    end

    private

    def process_line(line)
      parsed = LineProtocolParser.parse(line)
      return line unless parsed

      cache_fields(parsed)

      if house_power_sensor_match?(parsed)
        new_value = calculate_house_power(parsed.timestamp)
        @last_house_power = new_value if new_value
        return new_value ? LineProtocolParser.build(update_house_power(parsed, new_value)) : line
      end

      line
    end

    def cache_fields(parsed)
      parsed.fields.each do |field, value|
        key = "#{parsed.measurement}:#{field}"
        @cache.cache(key, value, parsed.timestamp)
      end
    end

    def house_power_sensor_match?(parsed)
      sensor = ENV.fetch('INFLUX_SENSOR_HOUSE_POWER', nil)
      return false unless sensor

      expected_measurement, expected_field = sensor.split(':')
      parsed.measurement == expected_measurement && parsed.fields.key?(expected_field)
    end

    def calculate_house_power(reference_ts)
      powers = {}
      HousePowerFormula::SENSORS.each do |sensor_key|
        sensor_env = ENV.fetch("INFLUX_SENSOR_#{sensor_key.to_s.upcase}", nil)
        next unless sensor_env

        value = @cache.fetch(sensor_env, reference_ts)
        powers[sensor_key] = value if value
      end
      HousePowerFormula.calculate(**powers)
    end

    def update_house_power(parsed, new_value)
      field_key = parsed.fields.keys.first
      parsed.fields = { field_key => new_value }
      parsed
    end
  end
end
