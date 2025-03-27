module DBConfig
  def self.file
    ENV.fetch('DB_FILE', 'data/production.sqlite3')
  end
end
