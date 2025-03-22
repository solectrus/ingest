ENV['APP_ENV'] = 'test'

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'rspec'
require 'rack/test'

require_relative '../lib/app'

RSpec.configure do |conf|
  conf.include Rack::Test::Methods
end
