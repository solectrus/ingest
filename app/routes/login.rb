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

      target = safe_return_to
      response.delete_cookie 'return_to'
      redirect to(target)
    else
      @error = 'Invalid, try again.'
      erb :login
    end
  end

  private

  # The browser sends the cookie, so a visitor can put any value in it.
  # Sinatra's `to` passes a value with a scheme through unchanged, which turns
  # the login into a redirect to a foreign host. Only a path stays.
  def safe_return_to
    target = request.cookies['return_to'].to_s

    target.match?(%r{\A/[^/\\]}) ? target : '/'
  end
end
