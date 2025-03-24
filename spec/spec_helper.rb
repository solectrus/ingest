ENV['APP_ENV'] = 'test'

require 'dotenv'
Dotenv.load('.env.test.local', '.env.test')

require 'boot'
require 'rspec'
require 'rack/test'
require 'sequel'

require_relative '../lib/store'
require_relative '../lib/app'

RSpec.configure { |conf| conf.include Rack::Test::Methods }

RSpec.configure do |config|
  config.before do
    STORE.db.drop_table?(:sensor_data)
    STORE.db.create_table :sensor_data do
      String :measurement, null: false
      String :field, null: false
      Integer :timestamp, null: false
      Integer :value_int
      Float :value_float
      TrueClass :value_bool
      String :value_string
      TrueClass :synced, default: false
      primary_key %i[measurement field timestamp]
      index :synced
    end
  end

  config.after { STORE.db.drop_table?(:sensor_data) }
end
