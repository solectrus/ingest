START_TIME = Time.current

module StatsHelpers # rubocop:disable Metrics/ModuleLength
  def incoming_total
    @incoming_total ||= Incoming.count
  end

  def outgoing_total
    @outgoing_total ||= Outgoing.count
  end

  def calculation_count
    Stats.counter(:house_power_recalculates)
  end

  def calculation_rate
    return unless calculation_count&.positive?

    60.0 * calculation_count / container_uptime
  end

  def calculation_cache_hits
    return unless calculation_count&.positive?

    100.0 * Stats.counter(:house_power_recalculate_cache_hits) / calculation_count
  end

  def response_time
    return unless Stats.counter(:http_requests).positive?

    (Stats.sum(:http_duration_total) / Stats.counter(:http_requests)).round
  end

  def format_duration(seconds) # rubocop:disable Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
    return '–' unless seconds

    time = Time.at(seconds).utc
    days = time.day - 1
    hours = time.hour
    minutes = time.min
    seconds = time.sec

    [
      ("#{days}d" if days.positive?),
      ("#{hours}h" if hours.positive? || days.positive?),
      ("#{minutes}m" if minutes.positive? || hours.positive?),
      ("#{seconds}s" if days.zero? && hours.zero?),
    ].compact.join(' ')
  end

  def database_size
    size_bytes = File.size?(Database.file)
    return '–' unless size_bytes

    size_bytes
  rescue StandardError => e
    # :nocov:
    e.message
    # :nocov:
  end

  def incoming_measurement_fields_grouped
    Incoming
      .distinct
      .pluck(:measurement, :field)
      .group_by(&:first)
      .transform_values { |pairs| pairs.map(&:last).sort }
  end

  def queue_oldest_age
    @queue_oldest_age ||= age_from(Outgoing.minimum(:created_at))
  end

  def incoming_range
    @incoming_range ||=
      range_between(
        Incoming.minimum(:created_at),
        Incoming.maximum(:created_at),
      )
  end

  def cache_range
    @cache_range ||=
      range_between(
        cache_stats[:oldest_timestamp]&./(1_000_000_000),
        cache_stats[:newest_timestamp]&./(1_000_000_000),
      )
  end

  def cache_size
    @cache_size ||= cache_stats[:size]
  end

  def cache_stats
    @cache_stats ||= SensorValueCache.instance.stats
  end

  def cache_age_for(measurement, field)
    timestamp = SensorValueCache.instance.timestamp_for(measurement, field)
    return unless timestamp

    age_from(timestamp / 1_000_000_000)
  end

  def incoming_throughput
    minutes = incoming_range&.fdiv(60)
    return 0 if minutes.nil? || minutes.zero?

    (incoming_total / minutes).round
  end

  def memory_usage
    return rss_from_ps_macos if macos?

    # Prefer cgroup usage if available (Docker etc.)
    if (cgroup_path = detect_cgroup_memory_path)
      return File.read(cgroup_path).to_i
    end

    # Fallback for LXC: /proc/self/status
    rss_from_procfs || 'N/A'
  rescue StandardError => e
    # :nocov:
    e.message
    # :nocov:
  end

  def cpu_usage # rubocop:disable Metrics/AbcSize
    cpu_seconds =
      if macos?
        time_str = `ps -o time= -p #{Process.pid}`.strip
        parse_time_to_seconds(time_str)
      elsif File.exist?('/sys/fs/cgroup/cpuacct/cpuacct.usage') # cgroup v1
        ns = File.read('/sys/fs/cgroup/cpuacct/cpuacct.usage').to_i
        ns / 1_000_000_000.0
      elsif File.exist?('/sys/fs/cgroup/cpu.stat') # cgroup v2
        usec =
          File.read('/sys/fs/cgroup/cpu.stat')[/usage_usec\s+(\d+)/, 1].to_i
        usec / 1_000_000.0
      else
        return 'N/A'
      end

    total_percent = (cpu_seconds / container_uptime) * 100
    total_percent / cpu_cores
  rescue StandardError => e
    # :nocov:
    e.message
    # :nocov:
  end

  def container_uptime
    @container_uptime ||= age_from(START_TIME)
  end

  def system_uptime
    @system_uptime ||=
      if macos?
        boot = `sysctl -n kern.boottime`.scan(/\d+/).first.to_i
        Time.current.to_i - boot
      else
        File.read('/proc/uptime').to_f
      end
  rescue StandardError => e
    # :nocov:
    e.message
    # :nocov:
  end

  def thread_count
    Thread.list.count
  end

  def disk_free
    available_kb = `df -k /`.lines[1].split[3].to_i
    available_kb * 1024
  rescue StandardError => e
    # :nocov:
    e.message
    # :nocov:
  end

  private

  def macos?
    RUBY_PLATFORM.include?('darwin')
  end

  def age_from(time)
    (Time.current - time).clamp(0, Float::INFINITY) if time
  end

  def range_between(start_time, end_time)
    end_time - start_time if start_time && end_time
  end

  def parse_time_to_seconds(str)
    parts = str.strip.split(':').map(&:to_i)
    case parts.size
    when 3
      (parts[0] * 3600) + (parts[1] * 60) + parts[2]
    when 2
      (parts[0] * 60) + parts[1]
    else
      0
    end
  end

  def cpu_cores
    macos? ? `sysctl -n hw.ncpu`.to_i : `nproc`.to_i
  rescue StandardError
    1
  end

  def detect_cgroup_memory_path
    paths = [
      '/sys/fs/cgroup/memory/memory.usage_in_bytes', # cgroups v1
      '/sys/fs/cgroup/memory.current', # cgroups v2
    ]
    paths.find { |p| File.exist?(p) }
  end

  def rss_from_procfs
    status = File.read('/proc/self/status')
    if (match = status.match(/^VmRSS:\s+(\d+)\s+kB/))
      match[1].to_i * 1024
    end
  end

  def rss_from_ps_macos
    rss_kb = `ps -o rss= -p #{Process.pid}`.lines.last.to_i
    rss_kb * 1024
  end
end
