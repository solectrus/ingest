require 'logger'

class App < Sinatra::Base
  set :logging, true

  logger = Logger.new($stdout)
  logger.level = Logger::DEBUG
  set :logger, logger

  before { env['rack.logger'] = settings.logger }

  use StatsRoute
  use WriteRoute
  use UpRoute

  [StatsRoute, WriteRoute, UpRoute].each do |route|
    route.set :logger, settings.logger
  end
end
