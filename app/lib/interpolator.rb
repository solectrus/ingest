class Interpolator
  # How much time one window covers. One window costs one query, and that
  # query reads every sample of its period. The period sets how many rows that
  # is, so this limit alone bounds the cost.
  MAX_WINDOW_SPAN_NS = 30.minutes.to_i * 1_000_000_000

  def initialize(sensor_keys:, timestamps:, max_age:)
    @timestamps = Array(timestamps).uniq.sort
    @max_age = max_age
    @sensors =
      sensor_keys
        .map { |key| [key, SensorEnvConfig[key]] }
        .reject do |_, config|
          config.nil? || config[:measurement].nil? || config[:field].nil?
        end
        .to_h
  end

  # Answers every timestamp of one call: { timestamp => { sensor_key => value } }
  def run
    return {} if sensors.empty? || timestamps.empty?

    windows.each_with_object({}) do |group, result|
      window =
        SampleWindow.load(
          pairs: sensor_pairs,
          first: group.first,
          last: group.last,
        )

      group.each do |timestamp|
        values = interpolate_all(window, timestamp)
        result[timestamp] = values if values.any?
      end
    end
  end

  private

  attr_reader :timestamps, :max_age, :sensors

  # Splits the sorted timestamps into groups that one query can answer. A group
  # ends when the next timestamp is too far from its first.
  def windows
    timestamps.each_with_object([]) do |timestamp, result|
      if result.empty? || timestamp - result.last.first > MAX_WINDOW_SPAN_NS
        result << [timestamp]
      else
        result.last << timestamp
      end
    end
  end

  # Two sensor keys can point to the same measurement and field, so the pairs
  # are deduplicated before the query is built.
  def sensor_pairs
    sensors.values.map { |conf| [conf[:measurement], conf[:field]] }.uniq
  end

  def interpolate_all(window, timestamp)
    sensors.each_with_object({}) do |(key, sensor), result|
      pair = [sensor[:measurement], sensor[:field]]
      value = interpolate_one(window.bounds(pair, timestamp), timestamp)
      result[key] = value if value
    end
  end

  def interpolate_one(bounds, timestamp)
    prev, nxt = bounds
    return unless prev

    # Two distinct samples bracket the target timestamp: linear
    # interpolation is valid regardless of sample age. Equal timestamps
    # would also cause a division by zero in #interpolate.
    return interpolate(prev, nxt, timestamp) if nxt && prev.timestamp != nxt.timestamp

    # No future sample yet — only accept prev as a flat extrapolation
    # if the sensor has reported recently enough.
    return if timestamp - prev.timestamp > max_age

    prev.value
  end

  def interpolate(prev, nxt, timestamp)
    v0 = prev.value
    v1 = nxt.value
    t0 = prev.timestamp
    t1 = nxt.timestamp

    v0 + ((v1 - v0) * (timestamp - t0).to_f / (t1 - t0))
  end
end
