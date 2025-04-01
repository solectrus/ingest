START_TIME = Time.current

module StatsHelpers # rubocop:disable Metrics/ModuleLength
  def incoming_total
    @incoming_total ||= Incoming.count
  end

  def outgoing_total
    @outgoing_total ||= Outgoing.count
  end

  def format_duration(seconds) # rubocop:disable Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
    return '–' unless seconds&.positive?

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

    number_to_human_size(size_bytes)
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

  def incoming_length
    @incoming_length ||=
      range_between(
        Incoming.minimum(:created_at),
        Incoming.maximum(:created_at),
      )
  end

  def incoming_throughput
    minutes = incoming_length&.fdiv(60)
    return 0 if minutes.nil? || minutes.zero?

    (incoming_total / minutes).round
  end

  def memory_usage
    if macos?
      rss_kb = `ps -o rss= -p #{Process.pid}`.lines.last.to_i

      return number_to_human_size(rss_kb * 1024)
    end

    path =
      if File.exist?('/sys/fs/cgroup/memory/memory.usage_in_bytes')
        '/sys/fs/cgroup/memory/memory.usage_in_bytes' # cgroups v1
      elsif File.exist?('/sys/fs/cgroup/memory.current')
        '/sys/fs/cgroup/memory.current' # cgroups v2
      end

    return 'N/A' unless path

    bytes = File.read(path).to_i
    number_to_human_size(bytes)
  rescue StandardError => e
    # :nocov:
    e.message
    # :nocov:
  end

  def cpu_usage # rubocop:disable Metrics/AbcSize
    total_percent =
      if macos?
        time_str = `ps -o time= -p #{Process.pid}`.strip
        seconds = parse_time_to_seconds(time_str)
        elapsed = Time.current - START_TIME
        (seconds / elapsed) * 100
      else
        usage_usec =
          File.read('/sys/fs/cgroup/cpu.stat')[/usage_usec\s+(\d+)/, 1].to_i
        cpu_seconds = usage_usec / 1_000_000.0

        start_time = File.read('/proc/1/stat').split[21].to_i
        hertz = `getconf CLK_TCK`.to_i
        system_uptime = File.read('/proc/uptime').split.first.to_f
        container_uptime = system_uptime - (start_time.to_f / hertz)

        (cpu_seconds / container_uptime) * 100
      end

    normalized = total_percent / cpu_cores
    "#{normalized.round(1)} %"
  rescue StandardError => e
    # :nocov:
    e.message
    # :nocov:
  end

  def container_uptime
    format_duration(Time.current - START_TIME)
  end

  def system_uptime
    seconds =
      if macos?
        boot = `sysctl -n kern.boottime`.scan(/\d+/).first.to_i
        Time.current.to_i - boot
      else
        File.read('/proc/uptime').to_f
      end

    format_duration(seconds)
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
    number_to_human_size(available_kb * 1024)
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
    Time.current - time if time
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
end
