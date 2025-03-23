require 'sqlite3'

class SensorDataStore
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
        value_type TEXT NOT NULL,
        PRIMARY KEY (measurement, field, timestamp)
      );
    SQL
    @db.execute('CREATE INDEX IF NOT EXISTS idx_sensor ON sensor_data (measurement, field, timestamp)')
  end

  def store(measurement:, field:, timestamp:, value:)
    case value
    when Integer
      @db.execute("INSERT OR REPLACE INTO sensor_data (measurement, field, timestamp, value_int, value_float, value_type)
                    VALUES (?, ?, ?, ?, ?, 'int')", [measurement, field, timestamp, value, value.to_f],)
    when Float
      @db.execute("INSERT OR REPLACE INTO sensor_data (measurement, field, timestamp, value_float, value_type)
                    VALUES (?, ?, ?, ?, 'float')", [measurement, field, timestamp, value],)
    when TrueClass, FalseClass
      @db.execute("INSERT OR REPLACE INTO sensor_data (measurement, field, timestamp, value_bool, value_type)
                    VALUES (?, ?, ?, ?, 'bool')", [measurement, field, timestamp, value ? 1 : 0],)
    else
      @db.execute("INSERT OR REPLACE INTO sensor_data (measurement, field, timestamp, value_string, value_type)
                    VALUES (?, ?, ?, ?, 'string')", [measurement, field, timestamp, value.to_s],)
    end
  end

  def interpolate(measurement:, field:, target_ts:)
    prev = @db.get_first_row("SELECT timestamp, value_float FROM sensor_data
                              WHERE measurement = ? AND field = ? AND timestamp <= ? AND value_float IS NOT NULL
                              ORDER BY timestamp DESC LIMIT 1", [measurement, field, target_ts],)

    nxt = @db.get_first_row("SELECT timestamp, value_float FROM sensor_data
                              WHERE measurement = ? AND field = ? AND timestamp >= ? AND value_float IS NOT NULL
                              ORDER BY timestamp ASC LIMIT 1", [measurement, field, target_ts],)

    return 0.0 unless prev || nxt

    if prev && nxt && prev['timestamp'] != nxt['timestamp']
      v1 = prev['value_float']
      t1 = prev['timestamp']
      v2 = nxt['value_float']
      t2 = nxt['timestamp']
      v1 + ((v2 - v1) * ((target_ts - t1).to_f / (t2 - t1)))
    elsif prev
      prev['value_float']
    else
      nxt['value_float']
    end
  end

  def cleanup(older_than_ts)
    @db.execute('DELETE FROM sensor_data WHERE timestamp < ?', [older_than_ts])
  end
end
