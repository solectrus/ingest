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
    now = Time.current
    timestamp = target.timestamp_ns(point.time || now.to_i)

    rows = point.fields.map do |field, value|
      {
        target_id: target.id,
        timestamp:,
        measurement: point.name,
        tags: point.tags,
        field:,
        created_at: now,
      }.merge(value_columns(value))
    end

    # Bulk insert rows without callbacks and validations
    Incoming.insert_all!(rows)

    # Callbacks are skipped by `insert_all!`, so we need to manually cache the values
    cache_values_from_rows(rows)
  end

  def cache_values_from_rows(rows)
    rows.each do |row|
      value = extract_value(row)
      next unless value

      SensorValueCache.instance.write(
        measurement: row[:measurement],
        field: row[:field],
        timestamp: row[:timestamp],
        value:,
      )
    end
  end

  def value_columns(value)
    {
      value_int: nil,
      value_float: nil,
      value_string: nil,
      value_bool: nil,
    }.tap do |result|
      case value
      when Integer               then result[:value_int] = value
      when Float                 then result[:value_float] = value
      when String                then result[:value_string] = value
      when TrueClass, FalseClass then result[:value_bool] = value
      else
        raise ArgumentError, "Unsupported value type: #{value.class}"
      end
    end
  end

  def extract_value(row)
    # We need to cache Integer and Float only
    row[:value_int] || row[:value_float]
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
