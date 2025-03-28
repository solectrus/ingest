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

  @config =
    SENSOR_KEYS
      .filter_map do |key|
        env_value = ENV.fetch("INFLUX_SENSOR_#{key.to_s.upcase}", nil)
        next if env_value.nil? || env_value.strip.empty?

        measurement, field = env_value.split(':', 2)
        [key, { measurement:, field: }]
      end
      .to_h

  @exclude_from_house_power_keys =
    ENV
      .fetch('INFLUX_EXCLUDE_FROM_HOUSE_POWER', '')
      .split(',')
      .map { it.strip.downcase }
      .to_set(&:to_sym)

  class << self
    SENSOR_KEYS.each { |key| define_method(key) { @config[key] } }

    attr_reader :config, :exclude_from_house_power_keys

    def sensor_keys_for_house_power
      @sensor_keys_for_house_power ||=
        SENSOR_KEYS.reject do
          it == :house_power || @exclude_from_house_power_keys.include?(it)
        end
    end

    def relevant_for_house_power?(parsed_line)
      sensor_keys_for_house_power.any? { parsed_line.fields.key?(it) }
    end
  end
end
