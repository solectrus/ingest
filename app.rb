class App < Sinatra::Base
  register SelectiveLogger

  # Every app in the chain runs a full Sinatra dispatch and its own
  # Rack::Protection stack before it hands the request on. The write route
  # takes almost all requests, so it goes first.
  use WriteRoute
  use HealthRoute
  use StatsRoute
  use LoginRoute
end
