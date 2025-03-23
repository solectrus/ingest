ENV['APP_ENV'] = 'test'

require 'boot'
require 'rspec'
require 'rack/test'
require 'sequel'

require_relative '../lib/store'
require_relative '../lib/app'

RSpec.configure { |conf| conf.include Rack::Test::Methods }

DB_TEST = Sequel.sqlite

RSpec.configure do |config|
  config.before do
    DB_TEST.create_table! :sensor_data do
      String :measurement, null: false
      String :field, null: false
      Integer :timestamp, null: false
      Integer :value_int
      Float :value_float
      TrueClass :value_bool
      String :value_string
      primary_key %i[measurement field timestamp]
    end
  end

  config.after { DB_TEST.drop_table?(:sensor_data) }
end
