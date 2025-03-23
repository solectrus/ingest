require_relative 'lib/boot'

ActiveRecord::MigrationContext.new('db/migrate').up

Thread.new { OutboxWorker.run_loop }
Thread.new { CleanupWorker.run_loop }

run App
