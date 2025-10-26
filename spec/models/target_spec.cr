require "../spec_helper"

describe Target do
  describe "#save!" do
    it "saves target to database" do
      target = Target.new
      target.bucket = "test-bucket"
      target.org = "test-org"
      target.influx_token = "test-token"
      target.precision = "ns"

      target.save!

      target.id.should_not be_nil
    end
  end

  describe ".find_by" do
    it "finds target by attributes" do
      target = create_target(
        bucket: "find-bucket",
        org: "find-org",
        influx_token: "find-token",
        precision: "ms"
      )

      found = Target.find_by(
        bucket: "find-bucket",
        org: "find-org",
        influx_token: "find-token",
        precision: "ms"
      )

      found.should_not be_nil
      found.not_nil!.id.should eq(target.id)
    end

    it "returns nil when not found" do
      found = Target.find_by(
        bucket: "nonexistent",
        org: "nonexistent",
        influx_token: "nonexistent",
        precision: "ns"
      )

      found.should be_nil
    end
  end

  describe "#timestamp_ns" do
    it "converts timestamp based on ns precision" do
      target = create_target(precision: "ns")
      result = target.timestamp_ns(1234567890)
      result.should eq(1234567890)
    end

    it "converts timestamp based on ms precision" do
      target = create_target(precision: "ms")
      result = target.timestamp_ns(1000)
      result.should eq(1_000 * 1_000_000)
    end
  end

  describe "#timestamp" do
    it "converts timestamp from ns based on ns precision" do
      target = create_target(precision: "ns")
      result = target.timestamp(1234567890_i64)
      result.should eq(1234567890_i64)
    end

    it "converts timestamp from ns based on ms precision" do
      target = create_target(precision: "ms")
      result = target.timestamp(1_000_000_000_i64)
      result.should eq(1_000_i64)
    end
  end
end
