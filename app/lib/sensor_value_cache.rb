class SensorValueCache
  include Singleton

  def initialize
    @cache = {}
    @mutex = Mutex.new
  end

  def write(measurement:, field:, timestamp:, value:)
    key = key_for(measurement, field)

    @mutex.synchronize do
      existing = @cache[key]
      return if existing && existing[:timestamp] > timestamp

      @cache[key] = { timestamp:, value: }
    end
  end

  def read(measurement:, field:, max_timestamp:, max_age:)
    key = key_for(measurement, field)

    data = @cache[key]
    return unless data
    return if data[:timestamp] > max_timestamp
    return if max_timestamp - data[:timestamp] > max_age

    data
  end

  # Drops every reading. The cache lives as long as the process, so a caller
  # that must not see what an earlier write left behind has to clear it.
  def reset!
    @mutex.synchronize { @cache.clear }
  end

  # Drops the reading of one sensor. The next read of it goes to the database
  # again.
  def delete(measurement:, field:)
    key = key_for(measurement, field)

    @mutex.synchronize do
      @cache.delete(key)
    end
  end

  def stats
    timestamps = @cache.values.map { |entry| entry[:timestamp] }

    {
      size: @cache.size,
      oldest_timestamp: timestamps.min,
      newest_timestamp: timestamps.max,
    }
  end

  private

  def key_for(measurement, field)
    [measurement, field]
  end
end
