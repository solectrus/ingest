class Processor
  def initialize(influx_token:, bucket:, org:, precision:)
    @target_args = { influx_token:, bucket:, org:, precision: }
  end

  def run(lines)
    points = LineBatch.new(lines).points
    return if points.empty?

    # Counted before the transaction runs. #drop_house_power removes a field
    # from a point, so the same count after the transaction is too low.
    values = points.sum { it.fields.size }
    replaced, calculated, enqueued = store(points)

    # After the transaction: a rollback keeps nothing, so it must count
    # nothing. One point is one line of the request, and one value is one
    # field of such a line. A line of 26 fields is thus 1 line and 26 values,
    # and it is 26 rows in the buffer.
    #
    # The replaced and the added house power make the balance of the
    # statistics page add up: the delivered values are the received ones, less
    # what Ingest dropped, plus what it calculated.
    Stats.inc(:incoming_lines, points.size)
    Stats.inc(:incoming_values, values)
    Stats.inc(:house_power_replaced, replaced)
    Stats.inc(:house_power_added, calculated)

    OutboxNotifier.notify! if enqueued || calculated.positive?
  end

  private

  # One transaction for the whole batch. A database error in the middle must
  # not keep the lines before it. The write route answers 500 for such an
  # error, and the client then retries the full batch. Without the transaction
  # the retry writes those lines a second time.
  #
  # The lock spans the transaction, because a writer that releases it early
  # lets a second writer run into the open transaction of the first.
  def store(points)
    replaced = calculated = 0
    enqueued = false

    Database.thread_safe_write do
      ActiveRecord::Base.transaction do
        now = Time.current

        store_incoming(points, now)
        replaced = drop_house_power(points)
        enqueued = outgoing_enqueued?(points, now)
        calculated = house_power_calculated(points, now)
      end
    end

    [replaced, calculated, enqueued]
  end

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
      # We need to cache Integer and Float only
      value = row[:value_int] || row[:value_float]
      next unless value

      SensorValueCache.instance.write(
        measurement: row[:measurement],
        field: row[:field],
        timestamp: row[:timestamp],
        value:,
      )
    end
  end

  def outgoing_enqueued?(points, now)
    rows =
      points.filter_map do |point|
        next if point.fields.empty?

        {
          target_id: target.id,
          line_protocol: point.to_line_protocol,
          values_count: point.fields.size,
          created_at: now,
        }
      end

    return false if rows.empty?

    Outgoing.insert_all!(rows)
    true
  end

  # Ingest calculates house power itself and replaces the incoming value, so
  # the incoming field never reaches InfluxDB.
  #
  # It returns how many fields it removed. The statistics page needs that
  # number: without it the page shows more delivered values than received
  # ones, and nothing on it explains the difference.
  def drop_house_power(points)
    house = SensorEnvConfig.house_power_destination
    return 0 unless house

    points.count do |point|
      point.name == house[:measurement] &&
        !point.fields.delete(house[:field]).nil?
    end
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
  # Returns how many lines it queued.
  def house_power_calculated(points, now)
    timestamps = house_power_timestamps(points, now)
    return 0 if timestamps.empty?

    HousePowerCalculator.new(target).recalculate_many(timestamps:)
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
