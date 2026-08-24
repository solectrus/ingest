require_relative 'boot'

if Sinatra::Base.environment == :development
  logger = Logger.new($stdout)
  logger.level = Logger::DEBUG
  ActiveRecord::Base.logger = logger
end

StartupMessage.print!

# A VACUUM rewrites the whole file. It ran on every boot before, at the moment
# the collectors flush their buffers into a container that just started.
unless Database.auto_vacuum_incremental?
  puts 'Compacting database...'
  Database.compact!
  puts 'Done.'
  puts
end

puts 'Checking database schema...'
context = ActiveRecord::MigrationContext.new('db/migrate')
if context.needs_migration?
  puts 'Applying migrations...'
  context.up
end
puts 'Up to date.'
puts

# The message comes from the caller, not from the thread. A thread prints when
# it gets scheduled, which is after the boot continues, so its line lands in
# the middle of the output of the web server.
def run_background_thread(name, &)
  puts "Starting #{name}..."

  Thread.new do
    Thread.current.name = name if Thread.current.respond_to?(:name=)

    loop do
      ActiveRecord::Base.connection_pool.with_connection(&)
    rescue StandardError => e
      warn "[#{name}] Error: #{e.class} - #{e.message}"
      warn e.backtrace.join("\n")
      sleep 5
      warn "[#{name}] Restarting..."
    end
  end
end

run_background_thread('OutboxWorker') { OutboxWorker.run_loop }
run_background_thread('CleanupWorker') { CleanupWorker.run_loop }
puts

run App
