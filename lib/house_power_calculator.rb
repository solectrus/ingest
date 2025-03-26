class HousePowerCalculator
  def initialize(target)
    @target = target
  end

  attr_reader :target

  def recalculate(timestamp:)
    powers = {}

    SensorEnvConfig::SENSOR_KEYS_FOR_HOUSE_POWER.each do |key|
      sensor = SensorEnvConfig.send(key)
      next unless sensor

      interpolated =
        Incoming.interpolate(
          measurement: sensor[:measurement],
          field: sensor[:field],
          timestamp:,
        )

      powers[key] = interpolated if interpolated
    end

    house_power = HousePowerFormula.calculate(**powers)
    return unless house_power

    line = build_line(house_power, timestamp)
    target.outgoings.create!(line_protocol: line)
  end

  private

  def build_line(house_power, timestamp)
    Line.new(
      measurement: SensorEnvConfig.house_power[:measurement],
      fields: {
        SensorEnvConfig.house_power[:field] => house_power.round,
      },
      timestamp:,
    ).to_s
  end
end
