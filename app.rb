require 'logger'

class App < Sinatra::Base
  set :logging, true
  set :logger, Logger.new($stdout)

  before { env['rack.logger'] = settings.logger }

  use StatsRoute
  use WriteRoute
  use UpRoute
end
