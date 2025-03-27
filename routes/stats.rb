class StatsRoute < BaseRoute
  if ENV['STATS_USERNAME'] && ENV['STATS_PASSWORD']
    use Rack::Auth::Basic, 'Restricted Area' do |username, password|
      username == ENV['STATS_USERNAME'] && password == ENV['STATS_PASSWORD']
    end
  end

  set :views, File.expand_path('../views', __dir__)
  helpers StatsHelpers, ActiveSupport::NumberHelper

  get '/' do
    erb :stats
  end
end
