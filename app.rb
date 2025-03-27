class App < Sinatra::Base
  use StatsRoute
  use WriteRoute
  use UpRoute
end
