$LOAD_PATH.unshift File.expand_path('..', __dir__)

require 'dotenv/load'
require 'sinatra/base'
require 'json'
require 'influxdb-client'
require 'sqlite3'
require 'active_record'

ActiveRecord::Base.establish_connection(
  adapter: 'sqlite3',
  database:
    ENV.fetch('APP_ENV', '') == 'test' ? ':memory:' : 'db/development.sqlite3',
)

require_relative '../db/schema'
require_relative '../models/target'
require_relative '../models/sensor'

require_relative 'app'
require_relative 'influx_writer'
require_relative 'store'
require_relative 'replay_worker'
require_relative 'house_power_formula'
require_relative 'line'
require_relative 'line_processor'
require_relative 'sensor_env_config'

STORE = Store.new
