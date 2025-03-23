$LOAD_PATH.unshift File.expand_path('..', __dir__)

require 'dotenv/load'
require 'sinatra/base'
require 'json'
require 'influxdb-client'
require 'sqlite3'

require_relative 'app'
require_relative 'influx_writer'
require_relative 'store'
require_relative 'house_power_calculator'
require_relative 'house_power_formula'
require_relative 'line_processor'
require_relative 'line_protocol_parser'
require_relative 'sensor_env_config'

STORE = Store.new(ENV['APP_ENV'] == 'test' ? ':memory:' : 'db/sensor_data.db')
