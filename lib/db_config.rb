module DBConfig
  def self.file
    ENV.fetch('DB_FILE', 'data/production.sqlite3')
  end

  WRITE_MUTEX = Mutex.new

  def self.thread_safe_db_write(&)
    WRITE_MUTEX.synchronize(&)
  end
end
