class HomeRoute < Sinatra::Base
  set :views, File.expand_path('../views', __dir__)
  helpers StatsHelpers, ActiveSupport::NumberHelper

  get '/' do
    erb :home
  end
end
