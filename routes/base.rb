require 'logger'

class BaseRoute < Sinatra::Base
  set :logging, true

  logger = Logger.new($stdout)
  logger.level = Logger::DEBUG
  set :logger, logger

  before { env['rack.logger'] = settings.logger }

  helpers do
    def protected!
      return if authorized?

      headers['WWW-Authenticate'] = 'Basic realm="Restricted Area"'
      halt 401, "Not authorized\n"
    end

    def authorized?
      return true unless username && password

      auth.provided? && auth.basic? && auth.credentials &&
        auth.credentials == [username, password]
    end

    def auth
      @auth ||= Rack::Auth::Basic::Request.new(request.env)
    end

    def username
      ENV.fetch('STATS_USERNAME', nil).presence
    end

    def password
      ENV.fetch('STATS_PASSWORD', nil).presence
    end
  end
end
