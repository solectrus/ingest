class Processor
  def initialize(influx_token:, bucket:, org:, precision:)
    @target_args = { influx_token:, bucket:, org:, precision: }
  end

  def run(lines)
    outbox_written = false

    lines.each do |line|
      point = Point.parse(line)

      Database.thread_safe_write do
        store_incoming(point)
        outbox_written |= enqueue_outgoing(point)
      end

      outbox_written |= trigger_house_power_if_relevant(point)
    end

    OutboxNotifier.notify! if outbox_written
  end

  private

  def target
    @target ||= Target.find_or_create_by!(**@target_args)
  end

  def store_incoming(point)
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

  def enqueue_outgoing(point)
    house = SensorEnvConfig.house_power_destination

    if point.name == house[:measurement] && point.fields.key?(house[:field])
      point.fields.delete(house[:field])
      return false if point.fields.empty?
    end

    Outgoing.create!(target:, line_protocol: point.to_line_protocol)
    true
  end

  def trigger_house_power_if_relevant(point)
    return false unless SensorEnvConfig.relevant_for_house_power?(point)

    HousePowerCalculator.new(target).recalculate(timestamp: point.time)
    true
  end
end
