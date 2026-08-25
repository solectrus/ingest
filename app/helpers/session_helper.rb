require 'openssl'
require 'active_support/security_utils'

module SessionHelper
  # The cookie carries this digest, not the password. A reader of the cookie
  # thus holds nothing that works anywhere else, and a new STATS_PASSWORD
  # invalidates every cookie that is out there.
  def self.token(password)
    OpenSSL::HMAC.hexdigest('SHA256', password, 'ingest/stats')
  end

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
    return true if password.nil?

    valid_token?(request.cookies['token'])
  end

  def session_token
    SessionHelper.token(password)
  end

  def valid_token?(given)
    secure_equal?(given, session_token)
  end

  def correct_password?(given)
    return false unless password

    secure_equal?(given, password)
  end

  def password
    ENV.fetch('STATS_PASSWORD', nil).presence
  end

  private

  # A plain == stops at the first byte that differs, so the time it takes tells
  # a caller how much of a guess is correct. secure_compare always reads the
  # full input.
  def secure_equal?(given, expected)
    ActiveSupport::SecurityUtils.secure_compare(given.to_s, expected)
  end
end
