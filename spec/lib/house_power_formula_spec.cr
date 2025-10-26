require "../spec_helper"

describe HousePowerFormula do
  describe ".calculate" do
    context "with single inverter" do
      it "uses total" do
        powers = {
          :inverter_power            => 100.0,
          :grid_import_power         => 50.0,
          :battery_discharging_power => 30.0,
          :battery_charging_power    => 20.0,
          :grid_export_power         => 10.0,
          :wallbox_power             => 5.0,
          :heatpump_power            => 15.0,
        }

        result = HousePowerFormula.calculate(powers)

        # 100 + 50 + 30 - 20 - 10 - 5 - 15 = 130
        result.should eq(130.0)
      end
    end

    context "with multiple inverters" do
      it "sums up parts" do
        powers = {
          :inverter_power_1          => 60.0,
          :inverter_power_2          => 40.0,
          :grid_import_power         => 50.0,
          :battery_discharging_power => 30.0,
          :battery_charging_power    => 20.0,
          :grid_export_power         => 10.0,
          :wallbox_power             => 5.0,
          :heatpump_power            => 15.0,
        }

        result = HousePowerFormula.calculate(powers)

        # (60 + 40) + 50 + 30 - 20 - 10 - 5 - 15 = 130
        result.should eq(130.0)
      end
    end

    context "with multiple inverters containing total" do
      it "uses total and ignores the parts" do
        powers = {
          :inverter_power            => 100.0,
          :inverter_power_1          => 60.0,
          :inverter_power_2          => 40.0,
          :grid_import_power         => 50.0,
          :battery_discharging_power => 30.0,
          :battery_charging_power    => 20.0,
          :grid_export_power         => 10.0,
          :wallbox_power             => 5.0,
          :heatpump_power            => 15.0,
        }

        result = HousePowerFormula.calculate(powers)

        # Uses inverter_power (100), not the sum of parts
        # 100 + 50 + 30 - 20 - 10 - 5 - 15 = 130
        result.should eq(130.0)
      end
    end

    it "returns 0 if result would be negative" do
      powers = {
        :inverter_power            => 10.0,
        :grid_import_power         => 0.0,
        :battery_discharging_power => 0.0,
        :battery_charging_power    => 0.0,
        :grid_export_power         => 100.0,
        :wallbox_power             => 0.0,
        :heatpump_power            => 0.0,
      }

      result = HousePowerFormula.calculate(powers)

      result.should eq(0.0)
    end

    it "raises on unknown keys" do
      powers = {
        :inverter_power => 100.0,
        :unknown_sensor => 50.0,
      }

      expect_raises(ArgumentError, /Unknown keys/) do
        HousePowerFormula.calculate(powers)
      end
    end
  end
end
