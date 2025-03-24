require_relative 'lib/boot'

namespace :db do
  desc 'Run pending migrations'
  task :migrate do
    context = ActiveRecord::MigrationContext.new('db/migrate')
    context.up
  end

  desc 'Rollback the last migration'
  task :rollback do
    context = ActiveRecord::MigrationContext.new('db/migrate')
    context.down
  end

  desc 'Show current schema version'
  task :version do
    context = ActiveRecord::MigrationContext.new('db/migrate')
    puts "Version: #{context.current_version}"
  end
end
