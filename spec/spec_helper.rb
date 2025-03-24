ENV['APP_ENV'] = 'test'

require 'dotenv'
Dotenv.load('.env.test.local', '.env.test')

require 'rspec'
require 'rack/test'
require 'active_record'

ENV['DB_FILE'] = ':memory:'
require_relative '../lib/boot'

ActiveRecord::MigrationContext.new('db/migrate').up

RSpec.configure { |conf| conf.include Rack::Test::Methods }

RSpec.configure do |config|
  config.before do
    Sensor.delete_all
    Target.delete_all
  end
end
