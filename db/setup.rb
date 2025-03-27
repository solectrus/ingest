class DatabaseSetup
  def self.run!
    ActiveRecord::Base.establish_connection(
      adapter: 'sqlite3',
      database: DBConfig.file,
    )
  end
end
