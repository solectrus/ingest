require 'logger'

class BaseRoute < Sinatra::Base
  set :logging, true

  logger = Logger.new($stdout)
  logger.level = Logger::DEBUG
  set :logger, logger

  before { env['rack.logger'] = settings.logger }
end
