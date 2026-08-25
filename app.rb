class App < Sinatra::Base
  register SelectiveLogger

  # The statistics page is 28 KB of markup, and it reloads every 30 seconds.
  # Gzip takes it to about 4 KB.
  #
  # It sits in front of the write route, because that route serves the static
  # files of the page as well, see BaseRoute. A collector sends no
  # Accept-Encoding, so its requests pass through untouched.
  use Rack::Deflater

  # Every app in the chain runs a full Sinatra dispatch and its own
  # Rack::Protection stack before it hands the request on. The write route
  # takes almost all requests, so it goes first.
  use WriteRoute
  use HealthRoute
  use StatsRoute
  use LoginRoute
end
