require 'logger'

class BaseRoute < Sinatra::Base
  set :logging, true
  set :views, File.expand_path('../views', __dir__)

  logger = Logger.new($stdout)
  logger.level = Logger::DEBUG
  set :logger, logger

  before { env['rack.logger'] = settings.logger }

  helpers SessionHelper

  PUBLIC_FOLDER = File.expand_path('../../public', __dir__)

  helpers do
    def build_info
      BuildInfo.to_s
    end

    # The browser caches the stylesheet, and an update ships a new one under
    # the same name. Without the stamp of the file, a reader gets the new
    # markup with the old CSS until that cache expires.
    def asset_path(file)
      "/#{file}?v=#{File.mtime(File.join(PUBLIC_FOLDER, file)).to_i}"
    end

    def h(text)
      Rack::Utils.escape_html(text)
    end
  end
end
