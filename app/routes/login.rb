class LoginRoute < BaseRoute
  get '/login' do
    erb :login
  end

  post '/login' do
    if params[:password] == password
      response.set_cookie 'password',
                          value: password,
                          path: '/',
                          httponly: true,
                          expires: 30.days.from_now

      target = request.cookies['return_to'] || '/'
      response.delete_cookie 'return_to'
      redirect to(target)
    else
      @error = 'Invalid, try again.'
      erb :login
    end
  end
end
