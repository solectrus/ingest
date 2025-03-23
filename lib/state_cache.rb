class StateCache
  VALID_TIME_WINDOW_NS = 5 * 60 * 1_000_000_000 # 5 minutes

  def initialize
    @state = {}
    @mutex = Mutex.new
  end

  def cache(key, value, timestamp)
    timestamp = normalize_timestamp(timestamp)
    @mutex.synchronize do
      current = @state[key]
      if current.nil? || timestamp > current[:timestamp]
        puts "Caching: #{key} = #{value} @ #{timestamp}"
        @state[key] = { value: value, timestamp: timestamp }
      else
        puts "Skip cache (older): #{key} = #{value} @ #{timestamp} (current ts: #{current[:timestamp]})"
      end
    end
  end

  # Fetches a value if it is within the valid time window
  def fetch(key, reference_ts)
    reference_ts = normalize_timestamp(reference_ts)
    @mutex.synchronize do
      data = @state[key]
      return nil unless data
      return nil if (reference_ts - data[:timestamp]) > VALID_TIME_WINDOW_NS

      data[:value]
    end
  end

  def reset
    @mutex.synchronize { @state.clear }
  end

  def stats
    @mutex.synchronize do
      { size: @state.size, keys: @state.keys.sort }
    end
  end

  private

  def normalize_timestamp(time)
    time = time.to_i
    time < 1_000_000_000_000_000_000 ? time * 1_000_000_000 : time
  end
end
