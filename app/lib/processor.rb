class Processor
  def initialize(influx_token:, bucket:, org:, precision:)
    @target_args = { influx_token:, bucket:, org:, precision: }
  end

  def run(lines)
    points = LineBatch.new(lines).points
    return if points.empty?

    outbox_written = false

    # One transaction for the whole batch. A database error in the middle must
    # not keep the lines before it. The write route answers 500 for such an
    # error, and the client then retries the full batch. Without the
    # transaction the retry writes those lines a second time.
    #
    # The lock spans the transaction, because a writer that releases it early
    # lets a second writer run into the open transaction of the first.
    Database.thread_safe_write do
      ActiveRecord::Base.transaction do
        now = Time.current

        store_incoming(points, now)
        outbox_written = outgoing_enqueued?(points, now)
        outbox_written |= house_power_recalculated?(points, now)
      end
    end

    # After the transaction: a rollback keeps nothing, so it must count
    # nothing. One point is one line of the request. The buffer counts a row
    # per field instead, and a line of 26 fields is 26 rows there.
    Stats.inc(:incoming_lines, points.size)

    OutboxNotifier.notify! if outbox_written
  end

  private

  def target
    @target ||= Target.fetch(**@target_args)
  end

  # The whole request goes to the database in one statement. One statement per
  # point held the write lock for 700 inserts of a 700 line request.
  def store_incoming(points, now)
    rows = points.flat_map { |point| incoming_rows(point, now) }

    # Bulk insert rows without callbacks and validations
    Incoming.insert_all!(rows)

    # Callbacks are skipped by `insert_all!`, so we need to manually cache the values
    cache_values_from_rows(rows)
  end

  def incoming_rows(point, now)
    timestamp = target.timestamp_ns(point.timestamp || now.to_i)

    point.fields.map do |field, value|
      {
        target_id: target.id,
        timestamp:,
        measurement: point.name,
        tags: point.tags,
        field:,
        created_at: now,
      }.merge(Incoming.value_columns(value))
    end
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

  def extract_value(row)
    # We need to cache Integer and Float only
    row[:value_int] || row[:value_float]
  end

  def outgoing_enqueued?(points, now)
    rows =
      points.filter_map do |point|
        drop_house_power(point)
        next if point.fields.empty?

        {
          target_id: target.id,
          line_protocol: point.to_line_protocol,
          created_at: now,
        }
      end

    return false if rows.empty?

    Outgoing.insert_all!(rows)
    true
  end

  # Ingest calculates house power itself and replaces the incoming value, so
  # the incoming field never reaches InfluxDB.
  def drop_house_power(point)
    house = SensorEnvConfig.house_power_destination
    return unless point.name == house[:measurement]

    point.fields.delete(house[:field])
  end

  # House power depends on every sensor at one point in time, so one timestamp
  # needs one calculation. A batch carries one line per sensor, and calculating
  # per line repeated the same work for every sensor of that timestamp.
  #
  # The calculation runs after the batch is stored. It then reads every sample
  # of the batch, not only the ones before the current line.
  #
  # The whole batch goes to the calculator at once, so it can answer every
  # timestamp with a few queries and queue the results in one statement.
  def house_power_recalculated?(points, now)
    timestamps = house_power_timestamps(points, now)
    return false if timestamps.empty?

    HousePowerCalculator.new(target).recalculate_many(timestamps:).positive?
  end

  def house_power_timestamps(points, now)
    points
      .filter_map do |point|
        next unless SensorEnvConfig.relevant_for_house_power?(point)

        # A line without a timestamp is stored under the time of the request,
        # so the calculation uses that same time.
        point.timestamp || now.to_i
      end
      .uniq
  end
end
