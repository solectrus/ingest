class App < Sinatra::Base
  use HomeRoute
  use WriteRoute
  use UpRoute
end
