class Database
  def self.file
    "data/#{Sinatra::Base.environment}.sqlite3"
  end

  def self.setup!
    ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: file)

    ActiveRecord::Base.connection.execute('PRAGMA journal_mode = WAL')
    ActiveRecord::Base.connection.execute('PRAGMA synchronous = NORMAL')

    ActiveRecord::Base.connection.execute('VACUUM')
  end

  WRITE_MUTEX = Mutex.new

  def self.thread_safe_write(&)
    WRITE_MUTEX.synchronize(&)
  end
end
