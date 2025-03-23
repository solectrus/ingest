require 'sqlite3'

class SensorDataStore
  DB_FILE = 'db/sensor_data.db'.freeze

  def initialize
    @db = SQLite3::Database.new(DB_FILE)
    @db.results_as_hash = true
    create_table
  end

  def create_table
    @db.execute <<~SQL
      CREATE TABLE IF NOT EXISTS sensor_data (
        measurement TEXT NOT NULL,
        field TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        value_int INTEGER,
        value_float REAL,
        value_bool BOOLEAN,
        value_string TEXT,
        value_type TEXT NOT NULL,
        PRIMARY KEY (measurement, field, timestamp)
      );
    SQL
    @db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sensor ON sensor_data (measurement, field, timestamp)',
    )
  end

  def store(measurement:, field:, timestamp:, value:)
    case value
    when Integer
      insert(
        'value_int',
        value,
        'int',
        measurement,
        field,
        timestamp,
        value.to_f,
      )
    when Float
      insert('value_float', value, 'float', measurement, field, timestamp)
    when TrueClass, FalseClass
      insert('value_bool', value ? 1 : 0, 'bool', measurement, field, timestamp)
    else
      insert(
        'value_string',
        value.to_s,
        'string',
        measurement,
        field,
        timestamp,
      )
    end
  end

  def interpolate(measurement:, field:, target_ts:)
    prev = fetch_neighbor(measurement, field, target_ts, '<=', 'DESC')
    nxt = fetch_neighbor(measurement, field, target_ts, '>=', 'ASC')

    return 0.0 unless prev || nxt

    if prev && nxt && prev['timestamp'] != nxt['timestamp']
      v1, t1 = prev.values_at('value_float', 'timestamp')
      v2, t2 = nxt.values_at('value_float', 'timestamp')
      v1 + ((v2 - v1) * ((target_ts - t1).to_f / (t2 - t1)))
    else
      (prev || nxt)['value_float']
    end
  end

  def cleanup(older_than_ts)
    @db.execute('DELETE FROM sensor_data WHERE timestamp < ?', [older_than_ts])
  end

  private

  def insert(
    column,
    value,
    type,
    measurement,
    field,
    timestamp,
    value_float = nil
  )
    sql = <<~SQL
      INSERT OR REPLACE INTO sensor_data
      (measurement, field, timestamp, #{column}, #{'value_float,' if value_float} value_type)
      VALUES (?, ?, ?, ?, #{'?, ' if value_float} ?)
    SQL
    params = [measurement, field, timestamp, value]
    params << value_float if value_float
    params << type
    @db.execute(sql, params)
  end

  def fetch_neighbor(measurement, field, target_ts, op, order)
    @db.get_first_row(<<~SQL, [measurement, field, target_ts])
      SELECT timestamp, value_float FROM sensor_data
      WHERE measurement = ? AND field = ? AND timestamp #{op} ? AND value_float IS NOT NULL
      ORDER BY timestamp #{order} LIMIT 1
    SQL
  end
end
