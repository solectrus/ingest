require 'logger'

class BaseRoute < Sinatra::Base
  set :logging, true
  set :views, File.expand_path('../views', __dir__)

  logger = Logger.new($stdout)
  logger.level = development? ? Logger::DEBUG : Logger::INFO # simplecov:disable branch — the specs run in the test environment
  set :logger, logger

  before { env['rack.logger'] = settings.logger }

  helpers SessionHelper

  # Sinatra derives the folder from the file of the app, which is this one.
  # That gives app/routes/public, a folder that does not exist.
  set :public_folder, File.expand_path('../../public', __dir__)

  # The page reloads every 30 seconds. Sinatra sent Last-Modified alone, so the
  # browser asked the server about the stylesheet, the script and every icon on
  # each of those reloads. That is a round trip per file for an answer of 304.
  #
  # One day, not one year: #asset_path stamps the stylesheet and the script
  # with their mtime, so a release reaches the browser under a new URL anyway,
  # but the icons carry no stamp and a year would freeze them.
  set :static_cache_control, [:public, { max_age: 1.day.to_i }]

  helpers do
    def build_info
      BuildInfo.to_s
    end

    # The browser caches the stylesheet, and an update ships a new one under
    # the same name. Without the stamp of the file, a reader gets the new
    # markup with the old CSS until that cache expires.
    def asset_path(file)
      "/#{file}?v=#{File.mtime(File.join(settings.public_folder, file)).to_i}"
    end

    def h(text)
      Rack::Utils.escape_html(text)
    end
  end
end
