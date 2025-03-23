class SensorEnvConfig
  SENSOR_KEYS = %i[
    inverter_power
    balcony_inverter_power
    grid_import_power
    grid_export_power
    battery_discharging_power
    battery_charging_power
    wallbox_power
    heatpump_power
    house_power
  ].freeze

  def self.load
    SENSOR_KEYS.to_h do |key|
      env_value = ENV.fetch("INFLUX_SENSOR_#{key.to_s.upcase}")
      measurement, field = env_value.split(':')
      [key, { measurement:, field: }]
    end
  end
end
