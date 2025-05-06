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

  def read(measurement:, field:, max_timestamp:)
    key = key_for(measurement, field)

    data = @cache[key]
    return unless data && data[:timestamp] <= max_timestamp

    data
  end

  if ENV['APP_ENV'] == 'test'
    def reset!
      @mutex.synchronize { @cache.clear }
    end

    def delete(measurement:, field:)
      key = key_for(measurement, field)

      @mutex.synchronize do
        @cache.delete(key)
      end
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
