module StatsHelpers
  def format_time(time)
    return '–' unless time

    time.getlocal.strftime('%Y-%m-%d %H:%M:%S')
  end

  def format_timestamp(nanoseconds)
    return '–' unless nanoseconds

    seconds = nanoseconds.to_i / 1_000_000_000.0
    format_time(Time.at(seconds))
  end

  def format_duration(seconds)
    return '–' unless seconds&.positive?

    minutes = (seconds / 60).to_i
    seconds = (seconds % 60).to_i

    minutes.zero? ? "#{seconds} s" : "#{minutes} min #{seconds} s"
  end

  def database_size
    size_bytes = File.size?(DBConfig.file)
    return '–' unless size_bytes

    size_mb = size_bytes.to_f / 1024 / 1024
    "#{size_mb.round(1)} MB"
  end

  def incoming_measurement_fields_grouped
    Incoming
      .distinct
      .pluck(:measurement, :field)
      .group_by(&:first)
      .transform_values { |pairs| pairs.map(&:last).sort }
  end

  def queue_oldest_age
    oldest = Outgoing.minimum(:created_at)
    return nil unless oldest

    Time.now - oldest
  end

  def incoming_newest_age
    newest = Incoming.maximum(:created_at)
    return nil unless newest

    Time.now - newest
  end
end
