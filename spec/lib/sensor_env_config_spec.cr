require "../spec_helper"

describe SensorEnvConfig do
  describe ".[]" do
    it "returns nil for unknown sensor" do
      result = SensorEnvConfig[:unknown_sensor]
      result.should be_nil
    end
  end

  describe ".house_power_destination" do
    it "returns sensor configuration" do
      result = SensorEnvConfig.house_power_destination
      result.should be_a(SensorEnvConfig::Sensor)
    end
  end

  describe ".sensor_keys_for_house_power" do
    it "returns array of symbols" do
      result = SensorEnvConfig.sensor_keys_for_house_power
      result.should be_a(Array(Symbol))
    end
  end

  describe ".relevant_for_house_power?" do
    it "returns boolean" do
      fields = {} of String => (Int64 | Float64 | String | Bool)
      fields["test"] = 42_i64
      point = Point.new(name: "test", fields: fields)

      result = SensorEnvConfig.relevant_for_house_power?(point)
      result.should be_a(Bool)
    end
  end

  describe ".exclude_from_house_power_keys" do
    it "returns set of symbols" do
      result = SensorEnvConfig.exclude_from_house_power_keys
      result.should be_a(Set(Symbol))
    end
  end
end
