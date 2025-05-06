class BuildInfo
  class << self
    def version
      @version ||= ENV.fetch('VERSION', nil).presence || 'unknown'
    end

    def revision
      @revision ||= ENV.fetch('REVISION', nil).presence
    end

    def built_at
      @built_at ||= ENV.fetch('BUILDTIME', nil).presence
    end

    def revision_short
      @revision_short ||= revision&.[](0, 7)
    end

    def to_s
      @to_s ||=
        if revision_short && built_at
          format(
            'Version %<version>s (%<rev>s), built at %<built>s',
            version:,
            rev: revision_short.presence || 'unknown',
            built: local_built_at.presence || 'unknown',
          )
        else
          format('Version %<version>s', version:)
        end
    end

    def local_built_at
      return if built_at.blank?

      tz = ENV['TZ'] || 'UTC'
      time = Time.parse(built_at)
      local = TZInfo::Timezone.get(tz).utc_to_local(time.utc)
      local.strftime('%Y-%m-%d %H:%M %Z')
    rescue TZInfo::InvalidTimezoneIdentifier
      built_at # fallback: original UTC-String
    end
  end
end
