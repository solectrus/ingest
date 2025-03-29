class HousePowerCalculator
  def initialize(target)
    @target = target
  end

  attr_reader :target

  def recalculate(timestamp:)
    sensor_keys = SensorEnvConfig.sensor_keys_for_house_power

    powers =
      Interpolator.new(
        timestamp: target.timestamp_ns(timestamp),
        sensor_keys:,
      ).run

    house_power = HousePowerFormula.calculate(**powers)
    return unless house_power

    write_house_power(house_power, timestamp)
  end

  private

  def write_house_power(house_power, timestamp)
    point =
      InfluxDB2::Point.new(
        name: SensorEnvConfig.house_power_destination[:measurement],
        fields: {
          SensorEnvConfig.house_power_destination[:field] => house_power.round,
        },
        time: timestamp,
        precision: target.precision,
      )

    Database.thread_safe_write do
      target.outgoings.create!(line_protocol: point.to_line_protocol)
    end
  end
end
