class Database
  def self.file
    "data/#{Sinatra::Base.environment}.sqlite3"
  end

  def self.pool_size
    puma_threads = ENV.fetch('PUMA_THREADS', 5).to_i
    extra_threads = 2 # OutboxWorker + CleanupWorker
    [puma_threads + extra_threads, 5].max
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
    ActiveRecord::Base.connection.execute('PRAGMA temp_store = MEMORY;')

    ActiveRecord::Base.connection.execute('VACUUM')
  end

  WRITE_MUTEX = Mutex.new

  def self.thread_safe_write(&)
    WRITE_MUTEX.synchronize(&)
  end
end
