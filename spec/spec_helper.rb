ENV['APP_ENV'] = 'test'

require 'simplecov'
SimpleCov.start

require 'dotenv'
Dotenv.load('.env.test.local', '.env.test')

require 'rspec'
require 'rack/test'
require 'active_record'

require_relative '../boot'

ActiveRecord::MigrationContext.new('db/migrate').up

RSpec.configure { |conf| conf.include Rack::Test::Methods }

RSpec.configure do |config|
  # Every example starts with empty global state, so the examples stay
  # independent of the order in which RSpec runs them.
  config.before do
    Incoming.delete_all
    Outgoing.delete_all
    Target.delete_all

    Target.reset!
    SensorValueCache.instance.reset!
    SensorEnvConfig.reset!
    OutboxNotifier.reset!
    Stats.reset!
  end

  config.before do
    $stdout = StringIO.new
    $stderr = StringIO.new
  end

  config.after do
    $stdout = STDOUT
    $stderr = STDERR
  end

  config.expect_with :rspec do |expectations|
    expectations.syntax = :expect
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.order = :random
  Kernel.srand config.seed
end

def login
  rack_mock_session.cookie_jar['token'] = SessionHelper.token(ENV.fetch('STATS_PASSWORD'))
end

def parsed_body
  JSON.parse(last_response.body)
end
