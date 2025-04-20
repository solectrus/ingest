class UpRoute < BaseRoute
  get '/up' do
    if request.head?
      status 200
    else
      content_type 'text/html'
      erb :up, layout: false
    end
  end
end
