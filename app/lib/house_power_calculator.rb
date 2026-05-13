class HousePowerCalculator
  MAX_SENSOR_AGE_NS = 15.minutes.to_i * 1_000_000_000
  SKIP_STAT_PREFIX = 'house_power_skip_'.freeze

  def initialize(target)
    @target = target
  end

  attr_reader :target

  def recalculate(timestamp:)
    Stats.inc(:house_power_recalculates)

    timestamp_ns = target.timestamp_ns(timestamp)

    powers = fetch_cached_powers(timestamp_ns)
    if powers
      Stats.inc(:house_power_recalculate_cache_hits)
    else
      powers = interpolate_powers(timestamp_ns)
      unless all_sensors_present?(powers)
        track_stale_skip(powers)
        return
      end
    end

    house_power = HousePowerFormula.calculate(**powers)
    return unless house_power

    write_house_power(house_power, timestamp_ns)
    Stats.set(:house_power_last_success_at, Time.current.to_i)
  end

  private

  def all_sensors_present?(powers)
    sensor_keys.all? { |key| powers.key?(key) }
  end

  def track_stale_skip(powers)
    missing = sensor_keys.reject { |key| powers.key?(key) }
    Stats.inc_many(
      [
        :house_power_recalculate_skipped,
        *missing.map { |key| :"#{SKIP_STAT_PREFIX}#{key}" },
      ],
    )
  end

  def fetch_cached_powers(timestamp_ns)
    sensor_keys.each_with_object({}) do |key, result|
      sensor = SensorEnvConfig[key]
      return nil unless sensor && sensor[:measurement] && sensor[:field]

      cached =
        SensorValueCache.instance.read(
          measurement: sensor[:measurement],
          field: sensor[:field],
          max_timestamp: timestamp_ns,
          max_age: MAX_SENSOR_AGE_NS,
        )

      return nil unless cached

      result[key] = cached[:value]
    end
  end

  def interpolate_powers(timestamp_ns)
    Interpolator.new(
      timestamp: timestamp_ns,
      sensor_keys:,
      max_age: MAX_SENSOR_AGE_NS,
    ).run
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
