class Stats
  @@mutex = Mutex.new
  @@counters = Hash(Symbol, Int64).new(0_i64)
  @@sums = Hash(Symbol, Float64).new(0.0)

  def self.inc(key : Symbol)
    @@mutex.synchronize { @@counters[key] += 1 }
  end

  def self.add(key : Symbol, value : Float64 | Int32)
    @@mutex.synchronize { @@sums[key] += value.to_f64 }
  end

  def self.counter(key : Symbol) : Int64
    @@mutex.synchronize { @@counters[key] }
  end

  def self.counters_by(prefix : Symbol | String) : Hash(Symbol, Int64)
    prefix_str = prefix.to_s
    @@mutex.synchronize do
      @@counters.select { |key, _| key.to_s.starts_with?(prefix_str) }
    end
  end

  def self.sum(key : Symbol) : Float64
    @@mutex.synchronize { @@sums[key] }
  end

  # For testing
  def self.reset!(key : Symbol? = nil)
    @@mutex.synchronize do
      if key
        @@counters.delete(key)
        @@sums.delete(key)
      else
        @@counters.clear
        @@sums.clear
      end
    end
  end
end
