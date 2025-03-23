$LOAD_PATH.unshift File.expand_path('..', __dir__)

require 'dotenv/load'
require 'sinatra/base'
require 'json'
require 'influxdb-client'
require 'sqlite3'

require_relative 'app'
require_relative 'influx_writer'
require_relative 'sensor_data_store'
require_relative 'house_power_service'
require_relative 'house_power_formula'
require_relative 'line_protocol_parser'
require_relative 'sensor_env_config'
