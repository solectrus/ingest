class StatsRoute < BaseRoute
  helpers StatsHelpers, ActiveSupport::NumberHelper

  get '/' do
    protected!
    erb :stats
  end
end
