class SensorEnvConfig
  # The order of the formula: first what brings power into the house, then
  # what takes it out, then the result. The statistics page lists the sensors
  # in this order on the sensors tab and the terms in the same order on the
  # house power tab, so a reader can read one against the other.
  KEYS = %i[
    inverter_power
    inverter_power_1
    inverter_power_2
    inverter_power_3
    inverter_power_4
    inverter_power_5
    grid_import_power
    battery_discharging_power
    battery_charging_power
    grid_export_power
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

    # The configured sensors that INFLUX_EXCLUDE_FROM_HOUSE_POWER names. The
    # formula ignores them, and SOLECTRUS subtracts them from the house power
    # again when it draws the dashboard.
    #
    # The house power is the result of the formula and never an input, so the
    # variable cannot exclude it. A name that no INFLUX_SENSOR_* variable
    # configures has no value to subtract, so it stays out too.
    def excluded_sensor_keys
      @excluded_sensor_keys ||=
        KEYS.select do |key|
          key != :house_power && config[key] &&
            exclude_from_house_power_keys.include?(key)
        end
    end

    def sensor_keys_for_house_power
      @sensor_keys_for_house_power ||=
        KEYS.reject do |key|
          key == :house_power || config[key].nil? ||
            exclude_from_house_power_keys.include?(key)
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

    # Drops the memoized configuration. The values come from the environment,
    # so a caller that changes it has to clear them.
    def reset!
      @config = nil
      @exclude_from_house_power_keys = nil
      @sensor_keys_for_house_power = nil
      @excluded_sensor_keys = nil
      @house_power_destination = nil
    end
  end
end
