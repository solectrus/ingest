# Load EnvLoader first (before any other requires)
require "./lib/env_loader"

# Load environment-specific .env file
env_file = ENV.fetch("KEMAL_ENV", ENV.fetch("APP_ENV", "production")) == "test" ? ".env.test" : ".env"
EnvLoader.load(env_file)

require "kemal"
require "db"
require "sqlite3"
require "log"
require "json"
require "ecr"

# Setup logging
Log.setup_from_env

# Require all source files
require "./config/**"
require "./lib/query_builder" # Must be loaded before models
require "./models/**"
require "./lib/**"
require "./workers/**"
require "./routes/**"

# Setup database
Database.setup!

# Print startup message
StartupMessage.print!

# Compact database
puts "Compacting database..."
Database.compact!
puts "Done."
puts

# Run migrations
puts "Checking database schema..."
if Database.needs_migration?
  puts "Applying migrations..."
  Database.migrate!
end
puts "Up to date."
puts

# Start background workers
spawn { OutboxWorker.run_loop }
spawn { CleanupWorker.run_loop }
puts

# Start web server
Kemal.config.port = ENV.fetch("PORT", "4567").to_i
Kemal.config.env = ENV.fetch("KEMAL_ENV", "production")
Kemal.run
