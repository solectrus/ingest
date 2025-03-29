module DBConfig
  def self.file
    "data/#{Sinatra::Base.environment}.sqlite3"
  end

  WRITE_MUTEX = Mutex.new

  def self.thread_safe_db_write(&)
    WRITE_MUTEX.synchronize(&)
  end
end
