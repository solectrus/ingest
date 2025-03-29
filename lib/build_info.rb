class BuildInfo
  def self.version = ENV.fetch('VERSION', nil)
  def self.revision = ENV.fetch('REVISION', nil)
  def self.built_at = ENV.fetch('BUILDTIME', nil)

  def self.revision_short
    return unless revision

    revision[0, 7]
  end

  def self.to_s
    format(
      'Version %<version>s (%<rev>s), built at %<built>s',
      version: version.presence || '<unknown>',
      rev: revision_short.presence || '<unknown>',
      built: local_built_at.presence || '<unknown>',
    )
  end

  def self.local_built_at
    return unless built_at

    tz = ENV['TZ'] || 'UTC'
    time = Time.parse(built_at)
    local = TZInfo::Timezone.get(tz).utc_to_local(time.utc)
    local.strftime('%Y-%m-%d %H:%M %Z')
  rescue TZInfo::InvalidTimezoneIdentifier
    built_at # fallback: original UTC-String
  end
end
