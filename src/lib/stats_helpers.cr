START_TIME = Time.utc

module StatsHelpers
  def incoming_total : Int64
    Incoming.count
  end

  def outgoing_total : Int64
    Outgoing.count
  end

  def calculation_count : Int64
    Stats.counter(:house_power_recalculates)
  end

  def calculation_rate : Float64?
    return unless calculation_count > 0

    60.0 * calculation_count / container_uptime
  end

  def calculation_cache_hits : Float64?
    return unless calculation_count > 0

    100.0 * Stats.counter(:house_power_recalculate_cache_hits) / calculation_count
  end

  def response_time : Int64?
    requests = Stats.counter(:http_requests)
    return unless requests > 0

    (Stats.sum(:http_duration_total) / requests).round.to_i64
  end

  def format_duration(seconds : Float64 | Int64 | Nil) : String
    return "–" unless seconds

    time = Time.unix(seconds.to_i64).to_utc
    days = time.day - 1
    hours = time.hour
    minutes = time.minute
    secs = time.second

    parts = [] of String
    parts << "#{days}d" if days > 0
    parts << "#{hours}h" if hours > 0 || days > 0
    parts << "#{minutes}m" if minutes > 0 || hours > 0
    parts << "#{secs}s" if days == 0 && hours == 0

    parts.join(" ")
  end

  def database_size : Int64
    File.size(Database.file)
  rescue
    0_i64
  end

  def incoming_measurement_fields_grouped : Hash(String, Array(NamedTuple(measurement: String, field: String, count: Int64)))
    results = [] of NamedTuple(measurement: String, field: String, count: Int64)

    Database.pool.query("SELECT measurement, field, COUNT(*) as count FROM incomings GROUP BY measurement, field") do |rs|
      rs.each do
        results << {
          measurement: rs.read(String),
          field:       rs.read(String),
          count:       rs.read(Int64),
        }
      end
    end

    results.group_by { |r| r[:measurement] }
  end

  def queue_oldest_age : Float64?
    age_from(queue_oldest_created_at)
  end

  private def queue_oldest_created_at : Time?
    result = Database.pool.query_one?("SELECT MIN(created_at) FROM outgoings", as: String)
    Time.parse_utc(result, "%Y-%m-%d %H:%M:%S.%N") if result
  rescue
    nil
  end

  def incoming_range : Float64?
    result = Database.pool.query_one?(
      "SELECT MIN(created_at), MAX(created_at) FROM incomings",
      as: {String?, String?}
    )
    return unless result

    min_str, max_str = result
    return unless min_str && max_str

    min_time = Time.parse_utc(min_str, "%Y-%m-%d %H:%M:%S.%N")
    max_time = Time.parse_utc(max_str, "%Y-%m-%d %H:%M:%S.%N")
    range_between(min_time, max_time)
  rescue
    nil
  end

  def cache_range : Float64?
    stats = cache_stats
    range_between(
      stats[:oldest_timestamp].try { |t| Time.unix(t // 1_000_000_000) },
      stats[:newest_timestamp].try { |t| Time.unix(t // 1_000_000_000) }
    )
  end

  def cache_size : Int64
    cache_stats[:size]
  end

  def cache_stats
    SensorValueCache.instance.stats
  end

  def incoming_throughput : Float64
    minutes = incoming_range.try(&./ 60)
    return 0.0 if minutes.nil? || minutes == 0

    (incoming_total / minutes).round(1)
  end

  def incoming_throughput_for(count : Int64) : Float64?
    return unless (range = incoming_range) && range > 0

    (60.0 * count / range).round(1)
  end

  def throughput_tag(value : Float64?) : String
    return "<small>-</small>" unless value

    css_class = if value <= 12
                  "ok"
                elsif value <= 24
                  "warn"
                else
                  "crit"
                end

    "<small class=\"#{css_class}\">#{number_to_delimited(value)} /min</small>"
  end

  def memory_usage : Int64 | String
    if macos?
      rss_from_ps_macos
    elsif (cgroup_path = detect_cgroup_memory_path)
      File.read(cgroup_path).to_i64
    else
      rss_from_procfs || "N/A"
    end
  rescue ex
    ex.message || "Error"
  end

  def cpu_usage : Float64 | String
    cpu_seconds = if macos?
                    time_str = `ps -o time= -p #{Process.pid}`.strip
                    parse_time_to_seconds(time_str)
                  elsif File.exists?("/sys/fs/cgroup/cpuacct/cpuacct.usage")
                    ns = File.read("/sys/fs/cgroup/cpuacct/cpuacct.usage").to_i64
                    ns / 1_000_000_000.0
                  elsif File.exists?("/sys/fs/cgroup/cpu.stat")
                    content = File.read("/sys/fs/cgroup/cpu.stat")
                    if match = content.match(/usage_usec\s+(\d+)/)
                      usec = match[1].to_i64
                      usec / 1_000_000.0
                    else
                      return "N/A"
                    end
                  else
                    return "N/A"
                  end

    total_percent = (cpu_seconds / container_uptime) * 100
    total_percent / cpu_cores
  rescue ex
    ex.message || "Error"
  end

  def container_uptime : Float64
    age_from(START_TIME) || 0.0
  end

  def system_uptime : Float64
    if macos?
      boot = `sysctl -n kern.boottime`.scan(/\d+/).first[0].to_i64
      Time.utc.to_unix - boot
    else
      File.read("/proc/uptime").to_f64
    end.to_f64
  rescue
    0.0
  end

  def thread_count : Int32
    # Crystal doesn't expose thread count easily, return fiber count as approximation
    1 # Placeholder
  end

  def disk_free : Int64
    available_kb = `df -k /`.lines[1].split[3].to_i64
    available_kb * 1024
  rescue
    0_i64
  end

  def number_to_delimited(number : Number, delimiter = ",") : String
    number.to_s.gsub(/(\d)(?=(\d{3})+(?!\d))/, "\\1#{delimiter}")
  end

  def number_to_percentage(number : Float64 | Int64 | String, precision = 2) : String
    return "–" if number.is_a?(String)

    "#{number.round(precision)}%"
  end

  def number_to_human_size(number : Int64 | String) : String
    return number if number.is_a?(String)

    units = ["B", "KB", "MB", "GB", "TB"]
    size = number.to_f64
    unit_index = 0

    while size >= 1024 && unit_index < units.size - 1
      size /= 1024
      unit_index += 1
    end

    "#{size.round(2)} #{units[unit_index]}"
  end

  private def macos? : Bool
    {% if flag?(:darwin) %}
      true
    {% else %}
      false
    {% end %}
  end

  private def age_from(time : Time?) : Float64?
    return unless time

    (Time.utc - time).total_seconds.clamp(0.0, Float64::MAX)
  end

  private def range_between(start_time : Time?, end_time : Time?) : Float64?
    return unless start_time && end_time

    (end_time - start_time).total_seconds
  end

  private def parse_time_to_seconds(str : String) : Float64
    parts = str.strip.split(':').map(&.to_i)
    case parts.size
    when 3
      (parts[0] * 3600) + (parts[1] * 60) + parts[2]
    when 2
      (parts[0] * 60) + parts[1]
    else
      0
    end.to_f64
  end

  private def cpu_cores : Int32
    if macos?
      `sysctl -n hw.ncpu`.to_i
    else
      `nproc`.to_i
    end
  rescue
    1
  end

  private def detect_cgroup_memory_path : String?
    paths = [
      "/sys/fs/cgroup/memory/memory.usage_in_bytes", # cgroups v1
      "/sys/fs/cgroup/memory.current",               # cgroups v2
    ]
    paths.find { |p| File.exists?(p) }
  end

  private def rss_from_procfs : Int64?
    status = File.read("/proc/self/status")
    if match = status.match(/^VmRSS:\s+(\d+)\s+kB/)
      match[1].to_i64 * 1024
    end
  rescue
    nil
  end

  private def rss_from_ps_macos : Int64
    rss_kb = `ps -o rss= -p #{Process.pid}`.lines.last.to_i64
    rss_kb * 1024
  end
end
