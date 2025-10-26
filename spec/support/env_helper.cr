module EnvHelper
  @@original_env = {} of String => String?

  def self.setup(vars : Hash(String, String | Nil))
    # Save original values
    @@original_env = vars.keys.to_h { |key| {key, ENV[key]?} }

    # Set new values
    vars.each do |key, value|
      if value
        ENV[key] = value
      else
        ENV.delete(key)
      end
    end
  end

  def self.teardown
    @@original_env.each do |key, value|
      if value
        ENV[key] = value
      else
        ENV.delete(key)
      end
    end
  end
end
