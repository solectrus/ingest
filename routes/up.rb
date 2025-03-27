class UpRoute < BaseRoute
  set :views, File.expand_path('../views', __dir__)

  get '/up' do
    content_type 'text/html'
    erb :up, layout: false
  end

  head '/up' do
    status 200
  end
end
