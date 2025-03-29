require_relative 'lib/boot'

ActiveRecord::MigrationContext.new('db/migrate').up

if Sinatra::Base.environment == :development
  logger = Logger.new($stdout)
  logger.level = Logger::DEBUG
  ActiveRecord::Base.logger = logger
end

StartupMessage.print!

Thread.new { OutboxWorker.run_loop }
Thread.new { CleanupWorker.run_loop }

run App
