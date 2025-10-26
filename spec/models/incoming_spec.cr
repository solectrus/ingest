require "../spec_helper"

describe Incoming do
  describe "#value=" do
    it "sets integer value" do
      incoming = Incoming.new
      incoming.value = 42_i64

      incoming.value_int.should eq(42)
    end

    it "sets float value" do
      incoming = Incoming.new
      incoming.value = 3.14

      incoming.value_float.should eq(3.14)
    end

    it "sets string value" do
      incoming = Incoming.new
      incoming.value = "hello"

      incoming.value_string.should eq("hello")
    end

    it "sets boolean true value" do
      incoming = Incoming.new
      incoming.value = true

      incoming.value_bool.should eq(true)
    end

    it "sets boolean false value" do
      incoming = Incoming.new
      incoming.value = false

      incoming.value_bool.should eq(false)
    end
  end

  describe "#value" do
    it "returns value_int when set" do
      incoming = Incoming.new
      incoming.value_int = 42_i64

      incoming.value.should eq(42)
    end

    it "returns value_float when set" do
      incoming = Incoming.new
      incoming.value_float = 3.14

      incoming.value.should eq(3.14)
    end

    it "returns value_string when set" do
      incoming = Incoming.new
      incoming.value_string = "hello"

      incoming.value.should eq("hello")
    end

    it "returns true when value_bool is true" do
      incoming = Incoming.new
      incoming.value_bool = true

      incoming.value.should eq(true)
    end

    it "returns false when value_bool is false" do
      incoming = Incoming.new
      incoming.value_bool = false

      incoming.value.should eq(false)
    end
  end

  describe "cache writing" do
    it "writes numeric values to cache after save" do
      SensorValueCache.instance.reset!
      target = create_target

      incoming = Incoming.new
      incoming.target_id = target.id.not_nil!
      incoming.measurement = "SENEC"
      incoming.field = "inverter_power"
      incoming.timestamp = target.timestamp_ns(1000_i64)
      incoming.value = 42.0
      incoming.save!

      cached = SensorValueCache.instance.read(
        measurement: "SENEC",
        field: "inverter_power",
        max_timestamp: target.timestamp_ns(1000_i64)
      )

      cached.should_not be_nil
      cached.not_nil!.value.should eq(42.0)
    end

    it "does not cache string values" do
      SensorValueCache.instance.reset!
      target = create_target

      incoming = Incoming.new
      incoming.target_id = target.id.not_nil!
      incoming.measurement = "SENEC"
      incoming.field = "system_status"
      incoming.timestamp = target.timestamp_ns(1000_i64)
      incoming.value = "It's all fine"
      incoming.save!

      cached = SensorValueCache.instance.read(
        measurement: "SENEC",
        field: "system_status",
        max_timestamp: target.timestamp_ns(1000_i64)
      )

      cached.should be_nil
    end

    it "does not cache boolean values" do
      SensorValueCache.instance.reset!
      target = create_target

      incoming = Incoming.new
      incoming.target_id = target.id.not_nil!
      incoming.measurement = "SENEC"
      incoming.field = "system_status_ok"
      incoming.timestamp = target.timestamp_ns(1000_i64)
      incoming.value = true
      incoming.save!

      cached = SensorValueCache.instance.read(
        measurement: "SENEC",
        field: "system_status_ok",
        max_timestamp: target.timestamp_ns(1000_i64)
      )

      cached.should be_nil
    end
  end
end
