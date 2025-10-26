class SensorValueCache
  record Entry, timestamp : Int64, value : Float64

  @@instance : SensorValueCache?
  @@mutex = Mutex.new

  def self.instance : SensorValueCache
    @@instance ||= new
  end

  @cache = Hash(Tuple(String, String), Entry).new
  @mutex = Mutex.new

  def write(measurement : String, field : String, timestamp : Int64, value : Float64)
    key = {measurement, field}

    @mutex.synchronize do
      existing = @cache[key]?
      return if existing && existing.timestamp > timestamp

      @cache[key] = Entry.new(timestamp: timestamp, value: value)
    end
  end

  def read(measurement : String, field : String, max_timestamp : Int64) : Entry?
    key = {measurement, field}

    data = @cache[key]?
    return unless data && data.timestamp <= max_timestamp

    data
  end

  # For testing
  def reset!
    @mutex.synchronize { @cache.clear }
  end

  def delete(measurement : String, field : String)
    key = {measurement, field}
    @mutex.synchronize { @cache.delete(key) }
  end

  def stats
    timestamps = @cache.values.map(&.timestamp)

    {
      size:             @cache.size.to_i64,
      oldest_timestamp: timestamps.min?,
      newest_timestamp: timestamps.max?,
    }
  end
end
