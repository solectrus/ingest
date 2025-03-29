class UpRoute < BaseRoute
  set :views, File.expand_path('../views', __dir__)

  get '/up' do
    if request.head?
      status 200
    else
      content_type 'text/html'
      erb :up, layout: false
    end
  end
end
