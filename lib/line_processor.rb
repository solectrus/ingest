class LineProcessor
  def initialize(influx_token, bucket, org, precision)
    @influx_token = influx_token
    @bucket = bucket
    @org = org
    @precision = precision || 'ns'
  end

  attr_reader :influx_token, :bucket, :org, :precision

  def process(influx_line)
    target_id = STORE.save_target(influx_token:, bucket:, org:, precision:)

    lines = influx_line.split("\n")
    lines.each { |line| process_and_store(line, target_id) }
  end

  private

  def process_and_store(line, target_id)
    parsed = Line.parse(line)

    parsed.fields.each do |field, value|
      STORE.save(
        measurement: parsed.measurement,
        field:,
        timestamp: parsed.timestamp,
        value:,
        target_id:,
      )
    end

    if house_power_trigger?(parsed)
      corrected = calculate_house_power(parsed.timestamp)
      if corrected
        parsed.fields[SensorEnvConfig.house_power[:field]] = corrected
        corrected_line = parsed.to_s
        write_influx(corrected_line)

        parsed.fields.each_key do |field|
          STORE.mark_synced(
            measurement: parsed.measurement,
            field: field,
            timestamp: parsed.timestamp,
            target_id: target_id,
          )
        end
      end
    else
      write_influx(line)
      parsed.fields.each_key do |field|
        STORE.mark_synced(
          measurement: parsed.measurement,
          field:,
          timestamp: parsed.timestamp,
          target_id:,
        )
      end
    end
  end

  def house_power_trigger?(parsed)
    house_sensor = SensorEnvConfig.house_power
    parsed.measurement == house_sensor[:measurement] &&
      parsed.fields.key?(house_sensor[:field])
  end

  def calculate_house_power(target_ts) # rubocop:disable Metrics/CyclomaticComplexity
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
      next unless config.is_a?(Hash)
      next unless config[:measurement] && config[:field]
      next if config[:measurement].empty? || config[:field].empty?

      value = STORE.interpolate(**config, target_ts:)
      powers[key] = value unless value.nil?
    end

    HousePowerFormula.calculate(**powers)
  end

  def write_influx(line)
    InfluxWriter.write(line, influx_token:, bucket:, org:, precision:)
  end
end
