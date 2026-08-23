class Database
  def self.file
    "data/#{Sinatra::Base.environment}.sqlite3"
  end

  def self.pool_size
    puma_threads = ENV.fetch('PUMA_THREADS', 5).to_i
    extra_threads = 2 # OutboxWorker + CleanupWorker
    [puma_threads + extra_threads, 10].max
  end

  def self.setup!
    ActiveRecord::Base.establish_connection(
      adapter: 'sqlite3',
      database: file,
      pool: pool_size,
      timeout: 5000,
    )

    ActiveRecord::Base.connection.execute('PRAGMA journal_mode = WAL')
    ActiveRecord::Base.connection.execute('PRAGMA synchronous = NORMAL')
    ActiveRecord::Base.connection.execute('PRAGMA temp_store = MEMORY')
    ActiveRecord::Base.connection.execute('PRAGMA auto_vacuum = INCREMENTAL')
  end

  AUTO_VACUUM_INCREMENTAL = 2

  # SQLite ignores `PRAGMA auto_vacuum` on a database that already holds data.
  # A VACUUM applies the mode, and the database keeps it from then on. So the
  # boot needs a VACUUM only for a database that a version without the mode
  # wrote.
  def self.auto_vacuum_incremental?
    ActiveRecord::Base.connection.select_value('PRAGMA auto_vacuum') ==
      AUTO_VACUUM_INCREMENTAL
  end

  def self.compact!
    ActiveRecord::Base.connection.execute('VACUUM')
  end

  def self.incremental_vacuum!(pages = 1000)
    ActiveRecord::Base.connection.execute("PRAGMA incremental_vacuum(#{pages})")
  end

  WRITE_MUTEX = Mutex.new

  # Serializes the writers. SQLite accepts one writer at a time, and the mutex
  # keeps the others out instead of letting them fail as busy.
  #
  # The lock is reentrant, because a caller can hold it for a whole batch and
  # still call a helper that locks for a single row. A plain `synchronize`
  # raises ThreadError for that.
  def self.thread_safe_write(&)
    return yield if WRITE_MUTEX.owned?

    WRITE_MUTEX.synchronize(&)
  end
end
