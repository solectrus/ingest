require "../spec_helper"

class TestStatsHelper
  include StatsHelpers
end

describe StatsHelpers do
  describe "#format_duration" do
    it "returns a dash for nil" do
      obj = TestStatsHelper.new
      obj.format_duration(nil).should eq("–")
    end

    it "formats seconds only" do
      obj = TestStatsHelper.new
      obj.format_duration(12_i64).should eq("12s")
    end

    it "formats minutes and seconds" do
      obj = TestStatsHelper.new
      obj.format_duration(75_i64).should eq("1m 15s")
    end

    it "formats hours and minutes" do
      obj = TestStatsHelper.new
      obj.format_duration((3600 + (2 * 60)).to_i64).should eq("1h 2m")
    end

    it "rounds down incomplete minutes and seconds" do
      obj = TestStatsHelper.new
      obj.format_duration(3661_i64).should eq("1h 1m")
    end
  end
end
