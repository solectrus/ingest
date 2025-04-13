module HousePowerFormula
  INVERTER_SENSORS = %i[
    inverter_power
    balcony_inverter_power
    inverter_power_1
    inverter_power_2
    inverter_power_3
    inverter_power_4
    inverter_power_5
  ].freeze
  private_constant :INVERTER_SENSORS
  # TODO: Remove balcony_inverter_power (use new config)

  OTHER_INCOMING_SENSORS = %i[
    grid_import_power
    battery_discharging_power
  ].freeze
  private_constant :OTHER_INCOMING_SENSORS

  INCOMING_SENSORS = INVERTER_SENSORS + OTHER_INCOMING_SENSORS
  private_constant :INCOMING_SENSORS

  OUTGOING_SENSORS = %i[
    battery_charging_power
    grid_export_power
    wallbox_power
    heatpump_power
  ].freeze
  private_constant :OUTGOING_SENSORS

  SENSORS = INCOMING_SENSORS + OUTGOING_SENSORS
  public_constant :SENSORS

  class << self
    # Calculates the corrected house power based on known sensor powers
    def calculate(**powers)
      validate_keys!(powers)

      incoming = incoming_power(powers)
      return if incoming.empty?

      outgoing = outgoing_power(powers)
      return if outgoing.empty?

      [incoming.sum - outgoing.sum, 0].max
    end

    private

    def incoming_power(powers)
      inverter_power(powers) +
        other_incoming_power(powers)
    end

    def inverter_power(powers)
      if powers[:balcony_inverter_power]
        # Deprecated config with balcony module (to be removed)
        [powers[:inverter_power], powers[:balcony_inverter_power]]
      elsif powers[:inverter_power]
        # New config, single inverter
        [powers[:inverter_power]]
      else
        # New config, multiple inverters
        (1..5).filter_map { powers[:"inverter_power_#{it}"] }
      end
    end

    def other_incoming_power(powers)
      OTHER_INCOMING_SENSORS.filter_map { powers[it] }
    end

    def outgoing_power(powers)
      OUTGOING_SENSORS.filter_map { powers[it] }
    end

    def validate_keys!(powers)
      unknown_keys = powers.keys - SENSORS
      return if unknown_keys.empty?

      raise ArgumentError, "Unknown keys: #{unknown_keys.join(', ')}"
    end
  end
end
