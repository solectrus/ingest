require "../spec_helper"

describe BuildInfo do
  describe "with all environment variables present" do
    before_each do
      EnvHelper.setup({
        "VERSION"   => "1.2.3",
        "REVISION"  => "abc123456789",
        "BUILDTIME" => "2025-03-29T08:00:00Z",
        "TZ"        => "Europe/Berlin",
      })
    end

    after_each { EnvHelper.teardown }

    it "returns the correct version" do
      BuildInfo.version.should eq("1.2.3")
    end

    it "returns the short revision" do
      BuildInfo.revision_short.should eq("abc1234")
    end

    it "formats local_built_at correctly" do
      # Europe/Berlin is UTC+1 (CET) or UTC+2 (CEST)
      # 08:00 UTC -> 09:00 or 10:00 local time
      result = BuildInfo.local_built_at
      result.should_not be_nil
      result.should match(/\A2025-03-29 (09|10):00 /)
    end

    it "returns a full formatted string" do
      result = BuildInfo.to_s
      result.should contain("Version 1.2.3")
      result.should contain("abc1234")
      result.should contain("2025-03-29")
    end
  end

  describe "with missing environment variables" do
    before_each do
      EnvHelper.setup({
        "VERSION"   => nil,
        "REVISION"  => nil,
        "BUILDTIME" => nil,
      })
    end

    after_each { EnvHelper.teardown }

    it "returns 'unknown' for version when not set" do
      BuildInfo.version.should eq("unknown")
    end

    it "returns nil for revision when not set" do
      BuildInfo.revision.should be_nil
    end

    it "returns nil for built_at when not set" do
      BuildInfo.built_at.should be_nil
    end

    it "returns 'Version unknown' in to_s" do
      BuildInfo.to_s.should eq("Version unknown")
    end
  end

  describe "with invalid timezone" do
    before_each do
      EnvHelper.setup({
        "VERSION"   => "1.0.0",
        "REVISION"  => "abcdef123456",
        "BUILDTIME" => "2025-03-29T08:00:00Z",
        "TZ"        => "invalid/timezone",
      })
    end

    after_each { EnvHelper.teardown }

    it "falls back to raw UTC string on invalid timezone" do
      BuildInfo.local_built_at.should eq("2025-03-29T08:00:00Z")
    end
  end
end
