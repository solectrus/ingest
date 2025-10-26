class Interpolator
  record Sample,
    measurement : String,
    field : String,
    timestamp : Int64,
    value : Float64,
    direction : String

  @sensors : Hash(Symbol, SensorEnvConfig::Sensor)

  def initialize(@sensor_keys : Array(Symbol), @timestamp : Int64)
    @sensors = @sensor_keys.compact_map do |key|
      config = SensorEnvConfig[key]
      next unless config

      {key, config}
    end.to_h
  end

  def run : Hash(Symbol, Float64)
    return {} of Symbol => Float64 if @sensors.empty?

    grouped_rows = load_grouped_rows
    interpolate_all(grouped_rows)
  end

  private def load_grouped_rows : Hash(Tuple(String, String), Array(Sample))
    sql = build_query
    samples = [] of Sample

    Database.pool.query(sql) do |rs|
      rs.each do
        measurement = rs.read(String)
        field = rs.read(String)
        timestamp = rs.read(Int64)
        # Read value as union type and convert to Float64
        raw_value = rs.read(Int64 | Float64)
        value = raw_value.is_a?(Int64) ? raw_value.to_f64 : raw_value
        direction = rs.read(String)

        samples << Sample.new(
          measurement: measurement,
          field: field,
          timestamp: timestamp,
          value: value,
          direction: direction
        )
      end
    end

    samples.group_by { |s| {s.measurement, s.field} }
  end

  private def build_where_clause : String
    grouped = @sensors.values.group_by(&.measurement)

    grouped.map do |measurement, fields|
      # Escape single quotes to prevent SQL injection
      escaped_measurement = measurement.gsub("'", "''")
      field_list = fields.map { |f| "'#{f.field.gsub("'", "''")}'" }.join(", ")
      "(measurement = '#{escaped_measurement}' AND field IN (#{field_list}))"
    end.join(" OR ")
  end

  private def build_query : String
    where = build_where_clause
    ts = @timestamp

    <<-SQL
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

  private def interpolate_all(grouped_rows : Hash(Tuple(String, String), Array(Sample))) : Hash(Symbol, Float64)
    result = {} of Symbol => Float64

    @sensors.each do |key, sensor|
      samples = grouped_rows[{sensor.measurement, sensor.field}]? || [] of Sample
      if (value = interpolate_one(samples))
        result[key] = value
      end
    end

    result
  end

  private def interpolate_one(samples : Array(Sample)) : Float64?
    prev, nxt = find_bounds(samples)
    return unless prev

    return prev.value if nxt.nil? || prev.timestamp == nxt.timestamp

    interpolate(prev, nxt)
  end

  private def find_bounds(samples : Array(Sample)) : Tuple(Sample?, Sample?)
    prev = samples.find { |r| r.direction == "prev" }
    nxt = samples.find { |r| r.direction == "next" }
    {prev, nxt}
  end

  private def interpolate(prev : Sample, nxt : Sample) : Float64
    v0 = prev.value
    v1 = nxt.value
    t0 = prev.timestamp
    t1 = nxt.timestamp

    v0 + ((v1 - v0) * (@timestamp - t0).to_f64 / (t1 - t0))
  end
end
