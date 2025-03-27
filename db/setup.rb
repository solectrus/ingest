class DatabaseSetup
  def self.run!
    ActiveRecord::Base.establish_connection(
      adapter: 'sqlite3',
      database: DBConfig.file,
    )

    ActiveRecord::Base.connection.execute('PRAGMA journal_mode = WAL')
    ActiveRecord::Base.connection.execute('PRAGMA synchronous = NORMAL')

    ActiveRecord::Base.connection.execute('VACUUM')
  end
end
