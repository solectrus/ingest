module StatsHelpers
  def format_duration(seconds)
    return '–' unless seconds&.positive?

    hours = (seconds / 3600).to_i
    minutes = ((seconds % 3600) / 60).to_i
    seconds = (seconds % 60).to_i

    if hours.positive?
      "#{hours}h #{minutes}m"
    elsif minutes.positive?
      "#{minutes}m #{seconds}s"
    else
      "#{seconds}s"
    end
  end

  def database_size
    size_bytes = File.size?(Database.file)
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

  def incoming_length
    first = Incoming.minimum(:created_at)
    last = Incoming.maximum(:created_at)
    return nil unless first && last

    last - first
  end
end
