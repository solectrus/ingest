START_TIME = Time.current

module StatsHelpers # rubocop:disable Metrics/ModuleLength
  def incoming_total
    @incoming_total ||= Incoming.count
  end

  def outgoing_total
    @outgoing_total ||= Outgoing.count
  end

  def format_duration(seconds) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
    return '–' unless seconds&.positive?

    days = (seconds / 86_400).to_i
    hours = (seconds % 86_400 / 3600).to_i
    minutes = (seconds % 3600 / 60).to_i
    seconds = (seconds % 60).to_i

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

    size_mb = size_bytes.to_f / 1024 / 1024
    "#{size_mb.round} MB"
  end

  def incoming_measurement_fields_grouped
    Incoming
      .distinct
      .pluck(:measurement, :field)
      .group_by(&:first)
      .transform_values { |pairs| pairs.map(&:last).sort }
  end

  def queue_oldest_age
    @queue_oldest_age ||=
      begin
        oldest = Outgoing.minimum(:created_at)

        Time.now - oldest if oldest
      end
  end

  def incoming_length
    @incoming_length ||=
      begin
        first = Incoming.minimum(:created_at)
        last = Incoming.maximum(:created_at)

        last - first if first && last
      end
  end

  def incoming_throughput
    total_time_in_minutes = incoming_length&.fdiv(60)
    return 0 if total_time_in_minutes.nil? || total_time_in_minutes.zero?

    (incoming_total / total_time_in_minutes).round
  end

  def memory_usage
    rss_kb =
      if macos?
        `ps -o rss= -p #{Process.pid}`.lines.last.to_i
      else
        `ps -o rss= -p #{Process.pid}`.to_i
      end

    "#{(rss_kb / 1024.0).round} MB"
  rescue StandardError => e
    # :nocov:
    e.message
    # :nocov:
  end

  def cpu_usage
    percent =
      if macos?
        `ps -o %cpu= -p #{Process.pid}`.to_f
      elsif File.exist?('/sys/fs/cgroup/cpu.stat')
        stats = File.read('/sys/fs/cgroup/cpu.stat')
        usage_usec = stats[/usage_usec\s+(\d+)/, 1].to_i
        uptime_s = File.read('/proc/uptime').split.first.to_f
        cpu_seconds = usage_usec / 1_000_000.0
        (cpu_seconds / uptime_s) * 100
      end

    percent ? "#{percent.round} %" : 'N/A'
  rescue StandardError => e
    # :nocov:
    e.message
    # :nocov:
  end

  def container_uptime
    seconds = Time.now - START_TIME

    format_duration(seconds)
  end

  def system_uptime
    seconds =
      if macos?
        boot = `sysctl -n kern.boottime`.scan(/\d+/).first.to_i
        Time.now.to_i - boot
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
    output = `df -k /`.lines[1]
    available_kb = output.split[3].to_i

    number_to_human_size available_kb * 1024
  rescue StandardError => e
    # :nocov:
    e.message
    # :nocov:
  end

  private

  def macos?
    RUBY_PLATFORM.include?('darwin')
  end
end
