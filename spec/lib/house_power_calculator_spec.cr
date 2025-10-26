require "../spec_helper"

describe HousePowerCalculator do
  describe "#recalculate" do
    target = uninitialized Target
    timestamp = 1_000_000_000_i64

    before_each do
      target = create_target
      timestamp_ns = target.timestamp_ns(timestamp)

      # Create Incoming for all relevant fields
      {
        {"SENEC", "inverter_power"}       => 500.0,
        {"SENEC", "bat_power_plus"}       => 200.0,
        {"SENEC", "bat_power_minus"}      => 0.0,
        {"SENEC", "grid_power_plus"}      => 0.0,
        {"SENEC", "grid_power_minus"}     => 0.0,
        {"SENEC", "wallbox_charge_power"} => 0.0,
        {"SENEC", "house_power"}          => 9999.0,
        {"balcony", "inverter_power"}     => 0.0,
        {"Heatpump", "power"}             => 0.0,
      }.each do |(measurement, field), value|
        Incoming.new(
          target_id: target.id.not_nil!,
          timestamp: timestamp_ns,
          measurement: measurement,
          field: field,
          value_float: value
        ).save!

        # Fill cache as Processor would do
        SensorValueCache.instance.write(
          measurement: measurement,
          field: field,
          timestamp: timestamp_ns,
          value: value
        )
      end
    end

    after_each do
      SensorValueCache.instance.reset!
      Stats.reset!
    end

    it "calculates house power and stores outgoing line" do
      calculator = HousePowerCalculator.new(target)
      timestamp_ns = target.timestamp_ns(timestamp)

      initial_count = Outgoing.count
      calculator.recalculate(timestamp)
      new_count = Outgoing.count

      (new_count - initial_count).should eq(1)

      outgoing = Outgoing.last.not_nil!
      outgoing.line_protocol.should eq("SENEC house_power=300i #{timestamp_ns}")
    end

    it "tracks recalculate" do
      calculator = HousePowerCalculator.new(target)

      Stats.counter(:house_power_recalculates).should eq(0)
      calculator.recalculate(timestamp)
      Stats.counter(:house_power_recalculates).should eq(1)
    end

    it "tracks cache hit" do
      calculator = HousePowerCalculator.new(target)

      calculator.recalculate(timestamp)
      Stats.counter(:house_power_recalculate_cache_hits).should eq(1)
    end

    it "tracks cache miss when requesting timestamp older than cache" do
      calculator = HousePowerCalculator.new(target)

      calculator.recalculate(timestamp - 1)
      Stats.counter(:house_power_recalculate_cache_hits).should eq(0)
    end

    it "tracks cache miss when one field is not in cache" do
      calculator = HousePowerCalculator.new(target)

      SensorValueCache.instance.delete(measurement: "SENEC", field: "grid_power_minus")
      calculator.recalculate(timestamp)
      Stats.counter(:house_power_recalculate_cache_hits).should eq(0)
    end
  end
end
