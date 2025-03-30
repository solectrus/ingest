class Processor
  def initialize(
    influx_token:,
    bucket:,
    org:,
    precision: InfluxDB2::WritePrecision::NANOSECOND
  )
    @target =
      Target.find_or_create_by!(influx_token:, bucket:, org:, precision:)
  end

  attr_reader :target

  def run(lines)
    lines.each do |line|
      point = Point.parse(line)

      store_incoming(point)
      enqueue_outgoing(point)
      trigger_house_power_if_relevant(point)
    end
  end

  private

  def store_incoming(point)
    Database.thread_safe_write do
      Incoming.transaction do
        point.fields.each do |field, value|
          target.incomings.create!(
            timestamp: target.timestamp_ns(point.time),
            measurement: point.name,
            tags: point.tags,
            field:,
            value:,
          )
        end
      end
    end
  end

  def enqueue_outgoing(point)
    fields_without_house_power =
      point.fields.reject do |field, _|
        point.name == SensorEnvConfig.house_power_destination[:measurement] &&
          field == SensorEnvConfig.house_power_destination[:field]
      end
    return if fields_without_house_power.empty?

    point_without_house_power =
      InfluxDB2::Point.new(
        name: point.name,
        tags: point.tags,
        fields: fields_without_house_power,
        time: point.time,
        precision: target.precision,
      )

    Database.thread_safe_write do
      Outgoing.create!(
        target:,
        line_protocol: point_without_house_power.to_line_protocol,
      )
    end
  end

  def trigger_house_power_if_relevant(point)
    return unless SensorEnvConfig.relevant_for_house_power?(point)

    HousePowerCalculator.new(target).recalculate(timestamp: point.time)
  end
end
