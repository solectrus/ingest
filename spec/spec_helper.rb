ENV['APP_ENV'] = 'test'

require 'simplecov'
require 'simplecov_json_formatter'
SimpleCov.start do
  formatter SimpleCov::Formatter::MultiFormatter.new(
    [
      SimpleCov::Formatter::JSONFormatter,
      SimpleCov::Formatter::HTMLFormatter,
    ],
  )
end

require 'dotenv'
Dotenv.load('.env.test.local', '.env.test')

require 'rspec'
require 'rack/test'
require 'active_record'

require_relative '../boot'

ActiveRecord::MigrationContext.new('db/migrate').up

RSpec.configure { |conf| conf.include Rack::Test::Methods }

RSpec.configure do |config|
  config.before do
    Incoming.delete_all
    Outgoing.delete_all
    Target.delete_all
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
end

def login
  rack_mock_session.cookie_jar['password'] = ENV.fetch('STATS_PASSWORD', nil)
end

def parsed_body
  JSON.parse(last_response.body)
end
