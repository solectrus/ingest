require 'logger'

class BaseRoute < Sinatra::Base
  set :logging, true
  set :views, File.expand_path('../views', __dir__)

  logger = Logger.new($stdout)
  logger.level = Logger::DEBUG
  set :logger, logger

  before { env['rack.logger'] = settings.logger }

  helpers SessionHelper

  helpers do
    def build_info
      BuildInfo.to_s
    end

    def h(text)
      Rack::Utils.escape_html(text)
    end
  end
end
