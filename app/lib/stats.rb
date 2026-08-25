class Stats
  @mutex = Mutex.new
  @counters = Hash.new(0)
  @sums = Hash.new(0)
  @values = {}

  class << self
    def inc(key, by = 1)
      @mutex.synchronize { @counters[key] += by }
    end

    def inc_many(keys)
      @mutex.synchronize { keys.each { |key| @counters[key] += 1 } }
    end

    def add(key, value)
      @mutex.synchronize { @sums[key] += value }
    end

    def set(key, value)
      @mutex.synchronize { @values[key] = value }
    end

    def counter(key)
      @mutex.synchronize { @counters[key] }
    end

    def counters_by(prefix)
      @mutex.synchronize do
        @counters.select { |key, _| key.to_s.start_with?(prefix.to_s) }
      end
    end

    def sum(key)
      @mutex.synchronize { @sums[key] }
    end

    def value(key)
      @mutex.synchronize { @values[key] }
    end

    # Clears the counter, the sum and the value of one key, or of every key if
    # no key is given.
    def reset!(key = nil)
      @mutex.synchronize do
        if key
          @counters.delete(key)
          @sums.delete(key)
          @values.delete(key)
        else
          @counters.clear
          @sums.clear
          @values.clear
        end
      end
    end
  end
end
