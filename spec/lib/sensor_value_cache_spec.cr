require "../spec_helper"

describe SensorValueCache do
  before_each do
    SensorValueCache.instance.reset!
  end

  describe "#write" do
    it "stores a value" do
      cache = SensorValueCache.instance

      cache.write(
        measurement: "test",
        field: "value",
        timestamp: 1000_i64,
        value: 42.0
      )

      entry = cache.read(
        measurement: "test",
        field: "value",
        max_timestamp: 2000_i64
      )

      entry.should_not be_nil
      entry.try(&.value).should eq(42.0)
    end

    it "doesn't overwrite with older timestamp" do
      cache = SensorValueCache.instance

      cache.write(
        measurement: "test",
        field: "value",
        timestamp: 2000_i64,
        value: 100.0
      )

      cache.write(
        measurement: "test",
        field: "value",
        timestamp: 1000_i64,
        value: 50.0
      )

      entry = cache.read(
        measurement: "test",
        field: "value",
        max_timestamp: 3000_i64
      )

      entry.should_not be_nil
      entry.try(&.value).should eq(100.0)
    end

    it "overwrites older value if timestamp is newer" do
      cache = SensorValueCache.instance

      cache.write(
        measurement: "test",
        field: "value",
        timestamp: 1000_i64,
        value: 1.0
      )

      cache.write(
        measurement: "test",
        field: "value",
        timestamp: 2000_i64,
        value: 2.0
      )

      entry = cache.read(
        measurement: "test",
        field: "value",
        max_timestamp: 3000_i64
      )

      entry.should_not be_nil
      entry.try(&.value).should eq(2.0)
    end
  end

  describe "#read" do
    it "returns nil for non-existent key" do
      cache = SensorValueCache.instance

      entry = cache.read(
        measurement: "nonexistent",
        field: "value",
        max_timestamp: 1000_i64
      )

      entry.should be_nil
    end

    it "returns nil if timestamp is too new" do
      cache = SensorValueCache.instance

      cache.write(
        measurement: "test",
        field: "value",
        timestamp: 2000_i64,
        value: 42.0
      )

      entry = cache.read(
        measurement: "test",
        field: "value",
        max_timestamp: 1000_i64
      )

      entry.should be_nil
    end
  end

  describe "#reset!" do
    it "clears the cache" do
      cache = SensorValueCache.instance

      cache.write(
        measurement: "test",
        field: "value",
        timestamp: 1000_i64,
        value: 42.0
      )

      # Verify it's stored
      entry = cache.read(
        measurement: "test",
        field: "value",
        max_timestamp: 2000_i64
      )
      entry.should_not be_nil

      # Reset and verify it's gone
      cache.reset!

      entry = cache.read(
        measurement: "test",
        field: "value",
        max_timestamp: 2000_i64
      )
      entry.should be_nil
    end
  end

  describe "#stats" do
    it "returns stats" do
      cache = SensorValueCache.instance

      cache.write("test1", "value", 1000_i64, 10.0)
      cache.write("test2", "value", 2000_i64, 20.0)
      cache.write("test3", "value", 1500_i64, 15.0)

      stats = cache.stats

      stats[:size].should eq(3)
      stats[:oldest_timestamp].should eq(1000_i64)
      stats[:newest_timestamp].should eq(2000_i64)
    end

    it "returns empty stats for empty cache" do
      cache = SensorValueCache.instance
      stats = cache.stats

      stats[:size].should eq(0)
      stats[:oldest_timestamp].should be_nil
      stats[:newest_timestamp].should be_nil
    end
  end
end
