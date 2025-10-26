module HousePowerFormula
  INVERTER_SENSORS = [
    :inverter_power,
    :inverter_power_1,
    :inverter_power_2,
    :inverter_power_3,
    :inverter_power_4,
    :inverter_power_5,
  ]

  OTHER_INCOMING_SENSORS = [
    :grid_import_power,
    :battery_discharging_power,
  ]

  INCOMING_SENSORS = INVERTER_SENSORS + OTHER_INCOMING_SENSORS

  OUTGOING_SENSORS = [
    :battery_charging_power,
    :grid_export_power,
    :wallbox_power,
    :heatpump_power,
  ]

  SENSORS = INCOMING_SENSORS + OUTGOING_SENSORS

  def self.calculate(powers : Hash(Symbol, Float64)) : Float64?
    validate_keys!(powers)

    incoming = incoming_power(powers)
    return if incoming.empty?

    outgoing = outgoing_power(powers)
    return if outgoing.empty?

    [incoming.sum - outgoing.sum, 0.0].max
  end

  private def self.incoming_power(powers : Hash(Symbol, Float64)) : Array(Float64)
    inverter_power(powers) + other_incoming_power(powers)
  end

  private def self.inverter_power(powers : Hash(Symbol, Float64)) : Array(Float64)
    if powers[:inverter_power]?
      # Single inverter
      [powers[:inverter_power]]
    else
      # Multiple inverters
      [
        :inverter_power_1,
        :inverter_power_2,
        :inverter_power_3,
        :inverter_power_4,
        :inverter_power_5,
      ].compact_map { |key| powers[key]? }
    end
  end

  private def self.other_incoming_power(powers : Hash(Symbol, Float64)) : Array(Float64)
    OTHER_INCOMING_SENSORS.compact_map { |key| powers[key]? }
  end

  private def self.outgoing_power(powers : Hash(Symbol, Float64)) : Array(Float64)
    OUTGOING_SENSORS.compact_map { |key| powers[key]? }
  end

  private def self.validate_keys!(powers : Hash(Symbol, Float64))
    unknown_keys = powers.keys - SENSORS
    return if unknown_keys.empty?

    raise ArgumentError.new("Unknown keys: #{unknown_keys.join(", ")}")
  end
end
