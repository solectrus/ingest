class App < Sinatra::Base
  register SelectiveLogger

  use StatsRoute
  use WriteRoute
  use UpRoute
end
