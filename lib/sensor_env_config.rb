class SensorEnvConfig
  KEYS = %i[
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

  class << self
    KEYS.each { |key| define_method(key) { config[key] } }

    def config
      @config ||=
        KEYS.each_with_object({}) do |key, hash|
          env_value = ENV.fetch("INFLUX_SENSOR_#{key.to_s.upcase}", nil)
          next if env_value.blank?

          measurement, field = env_value.split(':', 2)
          hash[key] = { measurement:, field: }
        end
    end

    def exclude_from_house_power_keys
      @exclude_from_house_power_keys ||=
        ENV
          .fetch('INFLUX_EXCLUDE_FROM_HOUSE_POWER', '')
          .split(',')
          .reject(&:blank?)
          .map(&:downcase)
          .to_set(&:to_sym)
    end

    def sensor_keys_for_house_power
      @sensor_keys_for_house_power ||=
        KEYS.reject do
          it == :house_power || exclude_from_house_power_keys.include?(it)
        end
    end

    def relevant_for_house_power?(parsed_line)
      sensor_keys_for_house_power.any? { parsed_line.fields.key?(it) }
    end
  end
end
