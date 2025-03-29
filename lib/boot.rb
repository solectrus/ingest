require 'dotenv/load'
require 'sinatra'
require 'sinatra/reloader' if Sinatra::Base.environment == :development
require 'json'
require 'influxdb-client'
require 'active_record'

$LOAD_PATH.unshift File.expand_path('..', __dir__)

%w[models helpers lib routes].each do |folder|
  Dir[File.join(__dir__, '..', folder, '**', '*.rb')].each { require it }
end

require_relative '../db/database'
Database.setup!

require 'app'
