ENV['APP_ENV'] = 'test'

require 'dotenv'
Dotenv.load('.env.test.local', '.env.test')

require 'rspec'
require 'rack/test'

require_relative '../lib/boot' # ⬅️ zentrales Boot

RSpec.configure { |conf| conf.include Rack::Test::Methods }

RSpec.configure do |config|
  config.before do
    Target.delete_all
    Sensor.delete_all
  end
end
