class HousePowerCalculator
  MAX_SENSOR_AGE_NS = 15.minutes.to_i * 1_000_000_000
  SKIP_STAT_PREFIX = 'house_power_skip_'.freeze

  def initialize(target)
    @target = target
  end

  attr_reader :target

  # Calculates house power for every timestamp of one request and queues the
  # results in one statement. Returns how many lines it queued.
  #
  # One timestamp at a time was used before. A backfill carries one timestamp
  # per collector poll, so a request of 5000 points made 5000 queries and 5000
  # inserts, all of them inside the write lock of the process.
  def recalculate_many(timestamps:)
    timestamps_ns = timestamps.map { target.timestamp_ns(it) }.uniq
    return 0 if timestamps_ns.empty?

    Stats.inc(:house_power_recalculates, timestamps_ns.size)

    rows = build_rows(powers_per_timestamp(timestamps_ns))
    return 0 if rows.empty?

    Database.thread_safe_write { Outgoing.insert_all!(rows) }
    Stats.set(:house_power_last_success_at, Time.current.to_i)
    rows.size
  end

  private

  # The cache answers a timestamp without a query, but it holds the newest
  # value of a sensor only. A backfill asks for older timestamps, so those
  # miss it. They go to the interpolator together, in one call.
  def powers_per_timestamp(timestamps_ns)
    result = {}
    uncached = []

    timestamps_ns.each do |timestamp_ns|
      if (powers = fetch_cached_powers(timestamp_ns))
        Stats.inc(:house_power_recalculate_cache_hits)
        result[timestamp_ns] = powers
      else
        uncached << timestamp_ns
      end
    end

    add_interpolated(result, uncached)
    result
  end

  def add_interpolated(result, timestamps_ns)
    return if timestamps_ns.empty?

    interpolated = interpolate_powers(timestamps_ns)

    timestamps_ns.each do |timestamp_ns|
      powers = interpolated[timestamp_ns] || {}
      missing = sensor_keys.reject { |key| powers.key?(key) }

      if missing.empty?
        result[timestamp_ns] = powers
      else
        track_stale_skip(missing)
      end
    end
  end

  def build_rows(powers)
    now = Time.current

    powers.filter_map do |timestamp_ns, sensor_powers|
      house_power = HousePowerFormula.calculate(**sensor_powers)
      next unless house_power

      {
        target_id: target.id,
        line_protocol: line_protocol(house_power, timestamp_ns),
        # One line, one field: the house power itself.
        values_count: 1,
        created_at: now,
      }
    end
  end

  def track_stale_skip(missing)
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

  def interpolate_powers(timestamps_ns)
    Interpolator.new(
      timestamps: timestamps_ns,
      sensor_keys:,
      max_age: MAX_SENSOR_AGE_NS,
    ).run
  end

  def line_protocol(house_power, timestamp_ns)
    InfluxDB2::Point.new(
      name: SensorEnvConfig.house_power_destination[:measurement],
      fields: {
        SensorEnvConfig.house_power_destination[:field] => house_power.round,
      },
      time: target.timestamp(timestamp_ns),
      precision: target.precision,
    ).to_line_protocol
  end

  def sensor_keys
    SensorEnvConfig.sensor_keys_for_house_power
  end
end
