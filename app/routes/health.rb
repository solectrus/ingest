class HealthRoute < BaseRoute
  get '/health' do
    if request.head?
      status 200
    else
      content_type 'text/html'
      erb :health, layout: false
    end
  end

  get '/ping' do
    status 204
  end
end
