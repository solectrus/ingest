class HousePowerCalculator
  def initialize(@target : Target)
  end

  def recalculate(timestamp : Int64)
    Stats.inc(:house_power_recalculates)

    timestamp_ns = @target.timestamp_ns(timestamp)

    powers = fetch_cached_powers(timestamp_ns)
    if powers
      Stats.inc(:house_power_recalculate_cache_hits)
    else
      # Fallback to interpolation from the database
      powers = interpolate_powers(timestamp_ns)
    end

    house_power = HousePowerFormula.calculate(powers)
    return unless house_power

    write_house_power(house_power, timestamp_ns)
  end

  private def fetch_cached_powers(timestamp_ns : Int64) : Hash(Symbol, Float64)?
    result = {} of Symbol => Float64

    sensor_keys.each do |key|
      sensor = SensorEnvConfig[key]
      return nil unless sensor

      cached = SensorValueCache.instance.read(
        measurement: sensor.measurement,
        field: sensor.field,
        max_timestamp: timestamp_ns
      )

      return nil unless cached

      result[key] = cached.value
    end

    result
  end

  private def interpolate_powers(timestamp_ns : Int64) : Hash(Symbol, Float64)
    Interpolator.new(timestamp: timestamp_ns, sensor_keys: sensor_keys).run
  end

  private def write_house_power(house_power : Float64, timestamp_ns : Int64)
    dest = SensorEnvConfig.house_power_destination

    fields = {} of String => (Int64 | Float64 | String | Bool)
    fields[dest.field] = house_power.round.to_i64

    point = Point.new(
      name: dest.measurement,
      fields: fields,
      tags: {} of String => String,
      time: @target.timestamp(timestamp_ns)
    )

    Database.thread_safe_write do
      outgoing = Outgoing.new
      outgoing.target_id = @target.id.not_nil!
      outgoing.line_protocol = point.to_line_protocol
      outgoing.save!
    end
  end

  private def sensor_keys : Array(Symbol)
    SensorEnvConfig.sensor_keys_for_house_power
  end
end
