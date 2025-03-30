require_relative 'lib/boot'

if Sinatra::Base.environment == :development
  logger = Logger.new($stdout)
  logger.level = Logger::DEBUG
  ActiveRecord::Base.logger = logger
end

StartupMessage.print!

puts 'Checking database...'
context = ActiveRecord::MigrationContext.new('db/migrate')
if context.needs_migration?
  puts 'Applying migrations...'
  context.up
end
puts 'Migrations are up to date!'

def run_background_thread(name)
  Thread.new do
    Thread.current.name = name if Thread.current.respond_to?(:name=)

    ActiveRecord::Base.connection_pool.with_connection do
      loop do
        puts "Starting #{name}..."
        yield
      rescue StandardError => e
        warn "[#{name}] Error: #{e.class} - #{e.message}"
        warn e.backtrace.join("\n")
        sleep 5
      end
    end
  end
end

sleep 1
run_background_thread('OutboxWorker') { OutboxWorker.run_loop }
run_background_thread('CleanupWorker') { CleanupWorker.run_loop }

sleep 1
puts 'Starting inbound server...'
run App
