class EnvLoader
  # Load .env file and set environment variables
  # Supports empty values (e.g., VARIABLE=)
  def self.load(file_path : String)
    return unless File.exists?(file_path)

    File.each_line(file_path) do |line|
      # Skip empty lines and comments
      next if line.strip.empty? || line.strip.starts_with?('#')

      # Match KEY=VALUE pattern (allowing empty values)
      if line =~ /^([A-Z_][A-Z0-9_]*)=(.*)$/
        key = $1
        value = $2.strip

        # Remove surrounding quotes if present
        value = value[1..-2] if value.starts_with?('"') && value.ends_with?('"')
        value = value[1..-2] if value.starts_with?('\'') && value.ends_with?('\'')

        # Only set if not already set (environment takes precedence)
        ENV[key] = value unless ENV.has_key?(key)
      end
    end
  end
end
