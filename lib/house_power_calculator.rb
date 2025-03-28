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
    line =
      Line.new(
        measurement: SensorEnvConfig.house_power[:measurement],
        fields: {
          SensorEnvConfig.house_power[:field] => house_power.round,
        },
        timestamp:,
      ).to_s

    target.outgoings.create!(line_protocol: line)
  end
end
