$LOAD_PATH.unshift File.expand_path('..', __dir__)

require 'dotenv/load'
require 'sinatra/base'
require 'json'
require 'influxdb-client'
require 'sqlite3'
require 'active_record'

DB_FILE = ENV.fetch('DB_FILE', 'db/production.sqlite3')
ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: DB_FILE)

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
