require "../spec_helper"

describe Interpolator do
  describe "#run" do
    it "returns interpolated values from real sensor config" do
      target = create_target
      timestamp = 1000_i64

      # Create incoming data points around the target timestamp
      # inverter_power: value at 990 = 1000, value at 1010 = 1200
      # Should interpolate to ~1100 at timestamp 1000
      incoming1 = Incoming.new
      incoming1.target_id = target.id.not_nil!
      incoming1.measurement = "SENEC"
      incoming1.field = "inverter_power"
      incoming1.timestamp = 990_i64
      incoming1.value = 1000.0
      incoming1.save!

      incoming2 = Incoming.new
      incoming2.target_id = target.id.not_nil!
      incoming2.measurement = "SENEC"
      incoming2.field = "inverter_power"
      incoming2.timestamp = 1010_i64
      incoming2.value = 1200.0
      incoming2.save!

      # wallbox_charge_power: only one value before timestamp
      incoming3 = Incoming.new
      incoming3.target_id = target.id.not_nil!
      incoming3.measurement = "SENEC"
      incoming3.field = "wallbox_charge_power"
      incoming3.timestamp = 980_i64
      incoming3.value = 0.0
      incoming3.save!

      result = Interpolator.new(
        sensor_keys: [:inverter_power, :wallbox_power],
        timestamp: timestamp
      ).run

      result[:inverter_power].should eq(1100.0)
      result[:wallbox_power].should eq(0.0)
    end

    it "returns empty hash when no sensors configured" do
      interpolator = Interpolator.new(
        sensor_keys: [] of Symbol,
        timestamp: 1000_i64
      )

      result = interpolator.run
      result.should be_empty
    end

    it "returns nothing if all sensors are missing" do
      result = Interpolator.new(
        sensor_keys: [:inverter_power_1, :grid_import_power],
        timestamp: 1000_i64
      ).run

      result.should be_empty
    end

    it "does not raise error when running with unconfigured sensors" do
      interpolator = Interpolator.new(
        sensor_keys: [:some_unknown_sensor],
        timestamp: 1234567890_i64
      )

      result = interpolator.run
      result.should be_empty
    end
  end
end
