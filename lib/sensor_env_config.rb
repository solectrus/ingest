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
    delegate :[], to: :config

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
          .map(&:strip)
          .reject(&:blank?)
          .map(&:downcase)
          .to_set(&:intern)
    end

    def sensor_keys_for_house_power
      @sensor_keys_for_house_power ||=
        KEYS.reject do |key|
          key == :house_power || exclude_from_house_power_keys.include?(key)
        end
    end

    def relevant_for_house_power?(point)
      sensor_keys_for_house_power.any? do |key|
        next unless (conf = config[key])

        point.name == conf[:measurement] && point.fields.key?(conf[:field])
      end
    end

    def house_power_destination
      @house_power_destination ||= house_power_calculated || self[:house_power]
    end

    def house_power_calculated
      string = ENV.fetch('INFLUX_SENSOR_HOUSE_POWER_CALCULATED', nil)
      return if string.blank?

      measurement, field = string.split(':', 2)
      { measurement:, field: }
    end
  end
end
