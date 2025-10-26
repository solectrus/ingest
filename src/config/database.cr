class Database
  WRITE_MUTEX = Mutex.new
  @@pool : DB::Database?

  def self.file
    env = ENV.fetch("KEMAL_ENV", "production")
    Dir.mkdir_p("data")
    "data/#{env}.sqlite3"
  end

  def self.pool : DB::Database
    @@pool ||= DB.open("sqlite3://#{file}")
  end

  def self.close_pool
    @@pool.try(&.close)
    @@pool = nil
  end

  def self.setup!
    pool.exec("PRAGMA journal_mode = WAL")
    pool.exec("PRAGMA synchronous = NORMAL")
    pool.exec("PRAGMA temp_store = MEMORY")
  end

  def self.compact!
    pool.exec("VACUUM")
  end

  def self.thread_safe_write(&block)
    WRITE_MUTEX.synchronize { yield }
  end

  def self.needs_migration?
    # Check if tables exist
    result = pool.query_one(
      "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='targets'",
      as: Int64
    )

    result == 0
  end

  def self.migrate!
    # Create targets table
    pool.exec <<-SQL
      CREATE TABLE IF NOT EXISTS targets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        bucket TEXT NOT NULL,
        org TEXT NOT NULL,
        influx_token TEXT NOT NULL,
        precision TEXT NOT NULL DEFAULT 'ns'
      )
    SQL

    # Create incomings table
    pool.exec <<-SQL
      CREATE TABLE IF NOT EXISTS incomings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        target_id INTEGER NOT NULL,
        measurement TEXT NOT NULL,
        field TEXT NOT NULL,
        tags TEXT NOT NULL DEFAULT '{}',
        timestamp INTEGER NOT NULL,
        value_int INTEGER,
        value_float REAL,
        value_bool INTEGER,
        value_string TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (target_id) REFERENCES targets(id)
      )
    SQL

    # Create indexes on incomings
    pool.exec "CREATE INDEX IF NOT EXISTS idx_incomings_measurement_field_timestamp ON incomings(measurement, field, timestamp)"
    pool.exec "CREATE INDEX IF NOT EXISTS idx_incomings_created_at ON incomings(created_at)"

    # Create outgoings table
    pool.exec <<-SQL
      CREATE TABLE IF NOT EXISTS outgoings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        target_id INTEGER NOT NULL,
        line_protocol TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (target_id) REFERENCES targets(id)
      )
    SQL
  end
end
