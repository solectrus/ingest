class HousePowerCalculator
  @count_recalculate = 0
  @cache_hits = 0

  class << self
    attr_reader :count_recalculate, :cache_hits

    def reset_stats
      @count_recalculate = 0
      @cache_hits = 0
    end

    def inc_recalculate
      @count_recalculate += 1
    end

    def inc_cache_hit
      @cache_hits += 1
    end
  end

  def initialize(target)
    @target = target
  end

  attr_reader :target

  def recalculate(timestamp:)
    self.class.inc_recalculate

    timestamp_ns = target.timestamp_ns(timestamp)

    # Try to get cached values first, because interpolation can be slow
    powers = fetch_cached_powers(timestamp_ns)
    if powers
      self.class.inc_cache_hit
    else
      # Fallback to interpolation from the database
      powers = interpolate_powers(timestamp_ns)
    end

    house_power = HousePowerFormula.calculate(**powers)
    return unless house_power

    write_house_power(house_power, timestamp_ns)
  end

  private

  def fetch_cached_powers(timestamp_ns)
    sensor_keys.each_with_object({}) do |key, result|
      sensor = SensorEnvConfig[key]
      return nil unless sensor && sensor[:measurement] && sensor[:field]

      cached =
        SensorValueCache.instance.read(
          measurement: sensor[:measurement],
          field: sensor[:field],
          max_timestamp: timestamp_ns,
        )

      return nil unless cached

      result[key] = cached[:value]
    end
  end

  def interpolate_powers(timestamp_ns)
    Interpolator.new(timestamp: timestamp_ns, sensor_keys:).run
  end

  def write_house_power(house_power, timestamp_ns)
    point =
      InfluxDB2::Point.new(
        name: SensorEnvConfig.house_power_destination[:measurement],
        fields: {
          SensorEnvConfig.house_power_destination[:field] => house_power.round,
        },
        time: target.timestamp(timestamp_ns),
        precision: target.precision,
      )

    Database.thread_safe_write do
      target.outgoings.create!(line_protocol: point.to_line_protocol)
    end
  end

  def sensor_keys
    SensorEnvConfig.sensor_keys_for_house_power
  end
end
