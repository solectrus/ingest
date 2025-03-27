module DBConfig
  def self.file
    ENV.fetch('DB_FILE', 'db/production.sqlite3')
  end
end
