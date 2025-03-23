class HousePowerCalculator
  SENSOR_STORE = SensorDataStore.new

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
        if numeric?(value)
          SENSOR_STORE.store(
            measurement: parsed.measurement,
            field:,
            timestamp: parsed.timestamp,
            value:,
          )
        end
      end

      if house_power_trigger?(parsed)
        corrected = calculate_house_power(parsed.timestamp)
        if corrected
          parsed.fields = { SensorEnvConfig.house_power[:field] => corrected }
          return LineProtocolParser.build(parsed)
        end
      end

      line
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

    def numeric?(val)
      val.is_a?(Integer) || val.is_a?(Float)
    end
  end
end
