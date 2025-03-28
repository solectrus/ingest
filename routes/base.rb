require 'logger'

class BaseRoute < Sinatra::Base
  set :logging, true

  logger = Logger.new($stdout)
  logger.level = Logger::DEBUG
  set :logger, logger

  before { env['rack.logger'] = settings.logger }

  helpers do
    def protected!
      return unless username && password
      return if authorized?

      headers['WWW-Authenticate'] = 'Basic realm="Restricted Area"'
      halt 401, "Not authorized\n"
    end

    def authorized?
      @auth ||= Rack::Auth::Basic::Request.new(request.env)

      @auth.provided? && @auth.basic? && @auth.credentials &&
        @auth.credentials == [username, password]
    end

    def username
      ENV.fetch('STATS_USERNAME', nil).presence
    end

    def password
      ENV.fetch('STATS_PASSWORD', nil).presence
    end
  end
end
