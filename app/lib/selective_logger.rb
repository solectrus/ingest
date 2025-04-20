module SelectiveLogger
  module Patch
    def log(env, status, headers, began_at)
      return if SelectiveLogger.skip_logging?(env, status)

      super
    end
  end

  def self.skip_logging?(env, status)
    return true if env['PATH_INFO'] == '/up'

    env['REQUEST_METHOD'] == 'POST' && env['PATH_INFO'] == '/api/v2/write' &&
      status == 204
  end

  def self.registered(_app)
    ::Rack::CommonLogger.prepend(Patch)
  end
end
