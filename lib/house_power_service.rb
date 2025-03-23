class HousePowerService
  STORE = Store.new

  def initialize(influx_token, bucket, org, precision)
    @influx_token = influx_token
    @bucket = bucket
    @org = org
    @precision = precision
  end

  def process(influx_line)
    lines = influx_line.split("\n")
    lines.each { |line| process_and_store(line) }
  end

  private

  def process_and_store(line)
    parsed = LineProtocolParser.parse(line)
    return unless parsed

    # Store all numeric fields into SQLite
    parsed.fields.each do |field, value|
      next unless numeric?(value)

      STORE.save(
        measurement: parsed.measurement,
        field:,
        timestamp: parsed.timestamp,
        value:,
      )
    end

    # Check if this line is the house_power sensor trigger
    if house_power_trigger?(parsed)
      corrected = calculate_house_power(parsed.timestamp)
      if corrected
        parsed.fields[SensorEnvConfig.house_power[:field]] = corrected
        return write_influx(LineProtocolParser.build(parsed))
      end
    end

    # Otherwise, forward unmodified
    write_influx(LineProtocolParser.build(parsed))
  end

  def house_power_trigger?(parsed)
    house_sensor = SensorEnvConfig.house_power
    parsed.measurement == house_sensor[:measurement] &&
      parsed.fields.key?(house_sensor[:field])
  end

  def calculate_house_power(target_ts)
    sensor_keys = %i[
      inverter_power
      balcony_inverter_power
      grid_import_power
      grid_export_power
      battery_discharging_power
      battery_charging_power
      wallbox_power
      heatpump_power
    ]

    powers = {}

    sensor_keys.each do |key|
      config = SensorEnvConfig.public_send(key)
      unless config.is_a?(Hash) &&
               config[:measurement]&.strip&.empty? == false &&
               config[:field]&.strip&.empty? == false
        next
      end

      value = STORE.interpolate(**config, target_ts:)
      powers[key] = value unless value.nil?
    end

    HousePowerFormula.calculate(**powers)
  end

  def write_influx(line)
    InfluxWriter.forward_influx_line(
      line,
      influx_token: @influx_token,
      bucket: @bucket,
      org: @org,
      precision: @precision,
    )
  end

  def numeric?(val)
    val.is_a?(Integer) || val.is_a?(Float)
  end
end
