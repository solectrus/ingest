class SensorEnvConfig
  SENSOR_KEYS_FOR_HOUSE_POWER = %i[
    inverter_power
    balcony_inverter_power
    grid_import_power
    grid_export_power
    battery_discharging_power
    battery_charging_power
    wallbox_power
    heatpump_power
  ].freeze

  SENSOR_KEYS = SENSOR_KEYS_FOR_HOUSE_POWER + %i[house_power].freeze

  @config =
    SENSOR_KEYS.to_h do |key|
      env_value = ENV.fetch("INFLUX_SENSOR_#{key.to_s.upcase}", nil)
      next key, nil unless env_value

      measurement, field = env_value.split(':', 2)
      [key, { measurement:, field: }]
    end

  class << self
    SENSOR_KEYS.each { |key| define_method(key) { @config[key] } }

    def relevant_for_house_power?(parsed_line)
      parsed_line
        .fields
        .keys
        .map(&:to_sym)
        .intersect?(SENSOR_KEYS_FOR_HOUSE_POWER)
    end
  end
end
