$stdout.sync = true

class App < Sinatra::Base
  set :logging, true

  use StatsRoute
  use WriteRoute
  use UpRoute
end
