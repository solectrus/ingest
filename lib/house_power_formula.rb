module HousePowerFormula
  INCOMING_SENSORS = %i[
    balcony_inverter_power
    inverter_power
    grid_import_power
    battery_discharging_power
  ].freeze
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

      incoming = INCOMING_SENSORS.filter_map { powers[it] }
      return if incoming.empty?

      outgoing = OUTGOING_SENSORS.filter_map { powers[it] }
      return if outgoing.empty?

      [incoming.sum - outgoing.sum, 0].max
    end

    private

    def validate_keys!(powers)
      unknown_keys = powers.keys - SENSORS
      return if unknown_keys.empty?

      raise ArgumentError, "Unknown keys: #{unknown_keys.join(', ')}"
    end
  end
end
