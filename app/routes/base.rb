require 'logger'

class BaseRoute < Sinatra::Base
  set :logging, true
  set :views, File.expand_path('../views', __dir__)

  logger = Logger.new($stdout)
  logger.level = Logger::DEBUG
  set :logger, logger

  before { env['rack.logger'] = settings.logger }

  helpers do
    def build_info
      BuildInfo.to_s
    end

    def h(text)
      Rack::Utils.escape_html(text)
    end

    def protected!
      return if authorized?

      if params.key?('unlock')
        if params[:unlock] == password
          response.set_cookie 'password', value: password, path: '/', httponly: true, expires: 30.days.from_now
          redirect to(request.path)
        else
          @error = 'Invalid, try again.'
        end
      end

      halt 401, erb(:unlock)
    end

    def authorized?
      password.nil? || request.cookies['password'] == password
    end

    def password
      ENV.fetch('STATS_PASSWORD', nil).presence
    end
  end
end
