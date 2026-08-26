# What the last house power calculation added up: the terms, the result, the
# value that the collector delivered, and the sensors that the formula leaves
# out. The statistics page prints the formula from this record, so a reader
# sees the values that produced the number Ingest wrote, and not an example of
# them.
#
# It lives beside the calculation and not inside it: the calculator computes,
# and what one page wants to show is a concern of its own.
class LastCalculation
  KEY = :house_power_last_calculation

  class << self
    def read
      Stats.value(KEY)
    end

    # Keeps one calculation, the newest one. A backfill computes old
    # timestamps now, and the page shows the present, so an older timestamp
    # must not replace what a newer one recorded.
    def record(timestamp_ns:, terms:, result:, source:)
      previous = read
      return if previous && previous[:timestamp_ns] >= timestamp_ns

      Stats.set(
        KEY,
        {
          timestamp_ns:,
          terms:,
          result:,
          source:,
          delivered: delivered_house_power(timestamp_ns),
          excluded: excluded_powers(timestamp_ns),
        }.freeze,
      )
    end

    private

    # The house power that the collector computed itself. Ingest drops that
    # value and writes its own in its place, so the two belong side by side:
    # the difference between them is the correction that Ingest exists for.
    #
    # The cache holds the delivered value even when Ingest overwrites the same
    # field. Processor stores the incoming lines, and the cache reads them,
    # before the house power is dropped from the point.
    def delivered_house_power(timestamp_ns)
      cached(:house_power, timestamp_ns)
    end

    # The sensors that INFLUX_EXCLUDE_FROM_HOUSE_POWER keeps out of the
    # formula. SOLECTRUS subtracts them from the house power again when it
    # draws the dashboard, so a reader sees a different value there than
    # Ingest writes. The page shows both, and it needs these for the second
    # one.
    #
    # A sensor that the cache cannot answer carries no value, and the page
    # then shows a dash instead of half a subtraction.
    def excluded_powers(timestamp_ns)
      SensorEnvConfig.excluded_sensor_keys.to_h do |key|
        [key, cached(key, timestamp_ns)]
      end
    end

    # The cache alone, never a query. The formula needs none of these values,
    # so a calculation must not wait for work that only the page wants.
    def cached(key, timestamp_ns)
      SensorValueCache.instance.read_sensor(
        key:,
        max_timestamp: timestamp_ns,
        max_age: HousePowerCalculator::MAX_SENSOR_AGE_NS,
      )
    end
  end
end
