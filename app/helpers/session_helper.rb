require 'active_support/security_utils'

module SessionHelper
  def protected!
    return if authorized?

    response.set_cookie 'return_to',
                        value: request.path == '/login' ? '/' : request.path,
                        path: '/',
                        httponly: true,
                        same_site: :lax,
                        secure: request.secure?
    redirect to('/login')
  end

  def authorized?
    password.nil? || correct_password?(request.cookies['password'])
  end

  # A plain == stops at the first byte that differs, so the time it takes tells
  # a caller how much of a guess is correct. secure_compare always reads the
  # full input.
  def correct_password?(given)
    return false unless password

    ActiveSupport::SecurityUtils.secure_compare(given.to_s, password)
  end

  def password
    ENV.fetch('STATS_PASSWORD', nil).presence
  end
end
