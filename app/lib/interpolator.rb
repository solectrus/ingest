class Interpolator # rubocop:disable Metrics/ClassLength
  Sample = Struct.new(:measurement, :field, :timestamp, :value, :direction)

  def initialize(sensor_keys:, timestamp:)
    @timestamp = timestamp
    @sensors =
      sensor_keys
        .map { |key| [key, SensorEnvConfig[key]] }
        .reject do |_, config|
          config.nil? || config[:measurement].nil? || config[:field].nil?
        end
        .to_h
  end

  def run
    return {} if sensors.empty?

    grouped_rows = load_grouped_rows
    interpolate_all(grouped_rows)
  end

  private

  attr_reader :timestamp, :sensors

  def load_grouped_rows
    sql = build_query
    rows = ActiveRecord::Base.connection.exec_query(sql)

    parse_rows(rows)
  end

  def build_where_clause
    connection = ActiveRecord::Base.connection

    grouped = sensors.values.group_by { |conf| conf[:measurement] }

    grouped
      .map do |measurement, fields|
        m = connection.quote(measurement)
        field_list = fields.map { |f| connection.quote(f[:field]) }.join(', ')
        "(measurement = #{m} AND field IN (#{field_list}))"
      end
      .join(' OR ')
  end

  def build_query
    connection = ActiveRecord::Base.connection
    where = build_where_clause
    ts = connection.quote(timestamp)

    <<~SQL.squish
      SELECT measurement,
             field,
             timestamp,
             value,
             direction
      FROM (
        SELECT measurement, field, timestamp,
               COALESCE(value_int, value_float) AS value,
               'prev' AS direction,
               ROW_NUMBER() OVER (
                 PARTITION BY measurement, field
                 ORDER BY timestamp DESC
               ) AS rnk
        FROM incomings
        WHERE timestamp <= #{ts}
          AND (#{where})

        UNION ALL

        SELECT measurement, field, timestamp,
               COALESCE(value_int, value_float) AS value,
               'next' AS direction,
               ROW_NUMBER() OVER (
                 PARTITION BY measurement, field
                 ORDER BY timestamp ASC
               ) AS rnk
        FROM incomings
        WHERE timestamp >= #{ts}
          AND (#{where})
      )
      WHERE rnk = 1
    SQL
  end

  def parse_rows(rows)
    mapped =
      rows.map do |row|
        Sample.new(
          row['measurement'],
          row['field'],
          row['timestamp'],
          row['value'],
          row['direction'],
        )
      end

    mapped.group_by { |row| [row.measurement, row.field] }
  end

  def interpolate_all(grouped_rows)
    sensors.each_with_object({}) do |(key, sensor), result|
      samples = grouped_rows[[sensor[:measurement], sensor[:field]]] || []
      value = interpolate_one(samples)
      result[key] = value if value
    end
  end

  def interpolate_one(samples)
    prev, nxt = find_bounds(samples)
    return unless prev
    return prev.value if nxt.nil? || prev.timestamp == nxt.timestamp

    interpolate(prev, nxt)
  end

  def find_bounds(samples)
    prev = samples.find { |r| r.direction == 'prev' }
    nxt = samples.find { |r| r.direction == 'next' }
    [prev, nxt]
  end

  def interpolate(prev, nxt)
    v0 = prev.value
    v1 = nxt.value
    t0 = prev.timestamp
    t1 = nxt.timestamp

    v0 + ((v1 - v0) * (timestamp - t0).to_f / (t1 - t0))
  end
end
