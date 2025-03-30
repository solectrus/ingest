class Interpolator
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
    placeholders = sensors.map { '(?, ?)' }.join(', ')
    values = sensors.values.flat_map { [it[:measurement], it[:field]] }

    sql = <<~SQL.squish
      SELECT *
      FROM (
        SELECT *,
               'prev' AS direction,
               ROW_NUMBER() OVER (PARTITION BY measurement, field ORDER BY timestamp DESC) AS rnk
        FROM incomings
        WHERE timestamp <= ?
          AND (measurement, field) IN (#{placeholders})

        UNION ALL

        SELECT *,
               'next' AS direction,
               ROW_NUMBER() OVER (PARTITION BY measurement, field ORDER BY timestamp ASC) AS rnk
        FROM incomings
        WHERE timestamp >= ?
          AND (measurement, field) IN (#{placeholders})
      )
      WHERE rnk = 1
    SQL

    rows =
      Incoming.find_by_sql([sql, timestamp] + values + [timestamp] + values)
    rows.group_by { |row| [row.measurement, row.field] }
  end

  def interpolate_all(grouped_rows)
    sensors.each_with_object({}) do |(key, sensor), result|
      samples = grouped_rows[[sensor[:measurement], sensor[:field]]] || []
      value = interpolate_one(samples)
      result[key] = value if value
    end
  end

  def interpolate_one(samples) # rubocop:disable Metrics/AbcSize
    prev = samples.find { |r| r.direction == 'prev' }
    nxt = samples.find { |r| r.direction == 'next' }

    return unless prev
    return prev.value if nxt.nil? || prev.timestamp == nxt.timestamp

    v0 = prev.value
    v1 = nxt.value
    t0 = prev.timestamp
    t1 = nxt.timestamp

    v0 + ((v1 - v0) * (timestamp - t0).to_f / (t1 - t0))
  end
end
