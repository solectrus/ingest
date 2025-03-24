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
    STORE.db.drop_table?(:targets)

    STORE.db.create_table? :targets do
      primary_key :id
      String :influx_token, null: false
      String :bucket, null: false
      String :org, null: false
      String :precision, null: false
      unique %i[influx_token bucket org precision]
    end

    STORE.db.create_table? :sensor_data do
      String :measurement, null: false
      String :field, null: false
      Integer :timestamp, null: false
      Integer :value_int
      Float :value_float
      TrueClass :value_bool
      String :value_string
      TrueClass :synced, default: false
      Integer :target_id, null: false
      foreign_key [:target_id], :targets
      primary_key %i[measurement field timestamp target_id]
      index %i[synced target_id]
    end
  end

  config.after do
    STORE.db.drop_table?(:sensor_data)
    STORE.db.drop_table?(:targets)
  end
end
