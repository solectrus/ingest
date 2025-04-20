module SessionHelper
  def protected!
    return if authorized?

    response.set_cookie 'return_to',
                        value: request.path == '/login' ? '/' : request.path,
                        path: '/',
                        httponly: true
    redirect to('/login')
  end

  def authorized?
    password.nil? || request.cookies['password'] == password
  end

  def password
    ENV.fetch('STATS_PASSWORD', nil).presence
  end
end
