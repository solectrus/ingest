class SensorEnvConfig
  KEYS = [
    :inverter_power,
    :inverter_power_1,
    :inverter_power_2,
    :inverter_power_3,
    :inverter_power_4,
    :inverter_power_5,
    :grid_import_power,
    :grid_export_power,
    :battery_discharging_power,
    :battery_charging_power,
    :wallbox_power,
    :heatpump_power,
    :house_power,
  ]

  record Sensor, measurement : String, field : String

  @@config : Hash(Symbol, Sensor)?

  def self.config : Hash(Symbol, Sensor)
    @@config ||= begin
      hash = {} of Symbol => Sensor

      KEYS.each do |key|
        env_value = ENV["INFLUX_SENSOR_#{key.to_s.upcase}"]?
        next if env_value.nil? || env_value.blank?

        parts = env_value.split(':', 2)
        next if parts.size != 2

        measurement, field = parts
        hash[key] = Sensor.new(measurement: measurement, field: field)
      end

      hash
    end
  end

  def self.[](key : Symbol) : Sensor?
    config[key]?
  end

  def self.exclude_from_house_power_keys : Set(Symbol)
    ENV.fetch("INFLUX_EXCLUDE_FROM_HOUSE_POWER", "")
      .split(',')
      .map(&.strip)
      .reject(&.blank?)
      .map { |s| :"#{s.downcase}" }
      .to_set
  end

  def self.sensor_keys_for_house_power : Array(Symbol)
    KEYS.reject do |key|
      key == :house_power ||
        config[key]?.nil? ||
        exclude_from_house_power_keys.includes?(key)
    end
  end

  def self.relevant_for_house_power?(point : Point) : Bool
    sensor_keys_for_house_power.any? do |key|
      conf = config[key]?
      next false unless conf

      point.name == conf.measurement && point.fields.has_key?(conf.field)
    end
  end

  def self.house_power_destination : Sensor
    house_power_calculated || self[:house_power] || raise "No house power destination configured"
  end

  def self.house_power_calculated : Sensor?
    string = ENV["INFLUX_SENSOR_HOUSE_POWER_CALCULATED"]?
    return if string.nil? || string.blank?

    parts = string.split(':', 2)
    return if parts.size != 2

    measurement, field = parts
    Sensor.new(measurement: measurement, field: field)
  end
end
