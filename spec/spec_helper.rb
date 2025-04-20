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
  config.before do
    Incoming.delete_all
    Outgoing.delete_all
    Target.delete_all
  end

  config.around do |example|
    original_stdout = $stdout
    original_stderr = $stderr
    $stdout = File.open(File::NULL, 'w')
    $stderr = File.open(File::NULL, 'w')
    example.run
  ensure
    $stdout = original_stdout
    $stderr = original_stderr
  end

  config.expect_with :rspec do |expectations|
    expectations.syntax = :expect
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
end
