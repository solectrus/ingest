require 'sqlite3'

class Store
  DB_FILE = 'db/sensor_data.db'.freeze

  def initialize
    @db = SQLite3::Database.new(DB_FILE)
    @db.results_as_hash = true
    create_table
  end

  def create_table
    @db.execute <<-SQL
      CREATE TABLE IF NOT EXISTS sensor_data (
        measurement TEXT NOT NULL,
        field TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        value_int INTEGER,
        value_float REAL,
        value_bool BOOLEAN,
        value_string TEXT,
        PRIMARY KEY (measurement, field, timestamp)
      );
    SQL
    @db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sensor ON sensor_data (measurement, field, timestamp)',
    )
  end

  def save(measurement:, field:, timestamp:, value:)
    case value
    when Integer
      @db.execute(<<-SQL, [measurement, field, timestamp, value, nil, nil, nil])
        INSERT OR REPLACE INTO sensor_data
        (measurement, field, timestamp, value_int, value_float, value_bool, value_string)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      SQL
    when Float
      @db.execute(<<-SQL, [measurement, field, timestamp, nil, value, nil, nil])
        INSERT OR REPLACE INTO sensor_data
        (measurement, field, timestamp, value_int, value_float, value_bool, value_string)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      SQL
    when TrueClass, FalseClass
      @db.execute(
        <<-SQL,
        INSERT OR REPLACE INTO sensor_data
        (measurement, field, timestamp, value_int, value_float, value_bool, value_string)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      SQL
        [measurement, field, timestamp, nil, nil, value ? 1 : 0, nil],
      )
    else
      @db.execute(
        <<-SQL,
        INSERT OR REPLACE INTO sensor_data
        (measurement, field, timestamp, value_int, value_float, value_bool, value_string)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      SQL
        [measurement, field, timestamp, nil, nil, nil, value.to_s],
      )
    end
  end

  def interpolate(measurement:, field:, target_ts:)
    prev = fetch_numeric_row(measurement, field, target_ts, '<=')
    nxt = fetch_numeric_row(measurement, field, target_ts, '>=')

    return 0.0 unless prev || nxt
    if prev && nxt && prev['timestamp'] != nxt['timestamp']
      return interpolate_between(prev, nxt, target_ts)
    end
    numeric_value(prev || nxt)
  end

  def cleanup(older_than_ts)
    @db.execute('DELETE FROM sensor_data WHERE timestamp < ?', [older_than_ts])
  end

  private

  def fetch_numeric_row(measurement, field, target_ts, operator)
    @db.get_first_row(<<-SQL, [measurement, field, target_ts])
      SELECT timestamp, value_int, value_float
      FROM sensor_data
      WHERE measurement = ? AND field = ? AND timestamp #{operator} ?
      AND (value_int IS NOT NULL OR value_float IS NOT NULL)
      ORDER BY timestamp #{operator == '<=' ? 'DESC' : 'ASC'}
      LIMIT 1
    SQL
  end

  def interpolate_between(prev, nxt, target_ts)
    v1, t1 = numeric_value(prev), prev['timestamp']
    v2, t2 = numeric_value(nxt), nxt['timestamp']
    return v1 if t1 == t2 # Fallback safety

    v1 + ((v2 - v1) * ((target_ts - t1).to_f / (t2 - t1)))
  end

  def numeric_value(row)
    return row['value_float'].to_f if row['value_float']
    return row['value_int'].to_f if row['value_int']

    0.0
  end
end
