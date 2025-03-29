class Processor
  def initialize(influx_token, bucket, org, precision = 'ns')
    @target =
      Target.find_or_create_by!(influx_token:, bucket:, org:, precision:)
  end

  attr_reader :target

  def run(influx_lines)
    influx_lines.each_line do |line|
      parsed = Line.parse(line)

      store_incoming(parsed)
      enqueue_outgoing(parsed)
      trigger_house_power_if_relevant(parsed)
    end
  end

  private

  def store_incoming(parsed)
    Database.thread_safe_write do
      Incoming.transaction do
        parsed.fields.each do |field, value|
          target.incomings.create!(
            timestamp: target.timestamp_ns(parsed.timestamp),
            measurement: parsed.measurement,
            tags: parsed.tags,
            field:,
            value:,
          )
        end
      end
    end
  end

  def enqueue_outgoing(parsed)
    fields_without_house_power =
      parsed.fields.reject do |field, _|
        parsed.measurement ==
          SensorEnvConfig.house_power_destination[:measurement] &&
          field.to_s == SensorEnvConfig.house_power_destination[:field]
      end
    return if fields_without_house_power.empty?

    line_without_house_power =
      Line.new(
        measurement: parsed.measurement,
        tags: parsed.tags,
        fields: fields_without_house_power,
        timestamp: parsed.timestamp,
      )

    Database.thread_safe_write do
      Outgoing.create!(target:, line_protocol: line_without_house_power.to_s)
    end
  end

  def trigger_house_power_if_relevant(parsed)
    return unless SensorEnvConfig.relevant_for_house_power?(parsed)

    HousePowerCalculator.new(target).recalculate(timestamp: parsed.timestamp)
  end
end
