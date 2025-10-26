class BuildInfo
  def self.version : String
    ENV.fetch("VERSION", "unknown")
  end

  def self.revision : String?
    ENV["REVISION"]?
  end

  def self.built_at : String?
    ENV["BUILDTIME"]?
  end

  def self.revision_short : String?
    revision.try(&.[0..6])
  end

  def self.to_s : String
    if (rev = revision_short) && (built = built_at)
      "Version #{version} (#{rev}), built at #{local_built_at || built}"
    else
      "Version #{version}"
    end
  end

  def self.local_built_at : String?
    return unless (built_str = built_at)

    tz = ENV.fetch("TZ", "UTC")
    time = Time.parse_utc(built_str, "%Y-%m-%dT%H:%M:%S%z")
    location = Time::Location.load(tz)
    local = time.in(location)
    local.to_s("%Y-%m-%d %H:%M %Z")
  rescue
    built_at # fallback: original UTC-String
  end
end
