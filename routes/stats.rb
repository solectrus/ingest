class StatsRoute < BaseRoute
  set :views, File.expand_path('../views', __dir__)
  helpers StatsHelpers, ActiveSupport::NumberHelper

  get '/' do
    protected!
    erb :stats
  end
end
