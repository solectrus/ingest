require 'bundler/setup'
require 'dotenv/load' if Gem.loaded_specs.key?('dotenv') # simplecov:disable branch — dotenv is always loaded in tests
require 'sinatra'
require 'json'
require 'influxdb-client'
require 'active_record'

%w[models helpers lib routes].each do |folder|
  Dir[File.join(__dir__, 'app', folder, '**', '*.rb')].each { require it }
end

require_relative 'db/database'
Database.setup!

require_relative 'app'
