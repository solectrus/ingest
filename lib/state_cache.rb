class StateCache
  VALID_TIME_WINDOW_NS = 5 * 60 * 1_000_000_000 # 5 minutes

  def initialize
    @state = {}
    @mutex = Mutex.new
  end

  # Stores a value with timestamp if newer
  def cache(key, value, timestamp)
    @mutex.synchronize do
      @state[key] = { value:, timestamp: } if @state[key].nil? || timestamp > @state[key][:timestamp]
    end
  end

  # Fetches a value if it is within the valid time window
  def fetch(key, reference_ts)
    @mutex.synchronize do
      data = @state[key]
      return nil unless data
      return nil if (reference_ts - data[:timestamp]) > VALID_TIME_WINDOW_NS

      data[:value]
    end
  end

  # Clears the state (for testing or reset)
  def reset
    @mutex.synchronize { @state.clear }
  end
end
