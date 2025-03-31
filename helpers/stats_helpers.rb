module StatsHelpers
  def incoming_total
    @incoming_total ||= Incoming.count
  end

  def outgoing_total
    @outgoing_total ||= Outgoing.count
  end

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
end
