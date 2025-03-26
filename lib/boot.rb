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
require_relative '../models/incoming'
require_relative '../models/outgoing'

require_relative 'app'
require_relative 'influx_writer'
require_relative 'house_power_calculator'
require_relative 'house_power_formula'
require_relative 'line'
require_relative 'processor'
require_relative 'sensor_env_config'
require_relative 'outbox_worker'
require_relative 'cleanup_worker'
