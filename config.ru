$LOAD_PATH.unshift File.expand_path('lib', __dir__)

require 'dotenv/load'
require 'sinatra/base'
require 'json'
require 'influxdb-client'
require 'sqlite3'

require 'app'
require 'influx_writer'
require 'sensor_data_store'
require 'house_power_service'
require 'house_power_formula'
require 'line_protocol_parser'
require 'sensor_env_config'

run App
