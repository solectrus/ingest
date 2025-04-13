require 'house_power_formula'

describe HousePowerFormula do
  describe '.calculate' do
    context 'with old config' do
      let(:powers) do
        {
          inverter_power: 3000,
          balcony_inverter_power: 200,
          grid_import_power: 500,
          battery_discharging_power: 200,
          battery_charging_power: 100,
          grid_export_power: 400,
          wallbox_power: 600,
          heatpump_power: 300,
        }
      end

      it 'calculates the correct house power' do
        result = described_class.calculate(**powers)
        incoming = 3000 + 200 + 500 + 200
        outgoing = 100 + 400 + 600 + 300
        expect(result).to eq(incoming - outgoing)
      end

      it 'returns nil if incoming is empty' do
        empty_powers =
          powers.except(
            :inverter_power,
            :balcony_inverter_power,
            :grid_import_power,
            :battery_discharging_power,
          )
        expect(described_class.calculate(**empty_powers)).to be_nil
      end

      it 'returns nil if outgoing is empty' do
        empty_powers =
          powers.except(
            :battery_charging_power,
            :grid_export_power,
            :wallbox_power,
            :heatpump_power,
          )
        expect(described_class.calculate(**empty_powers)).to be_nil
      end

      it 'raises ArgumentError for unknown keys' do
        expect { described_class.calculate(**powers, foo: 123) }.to raise_error(
          ArgumentError,
          /Unknown keys: foo/,
        )
      end
    end

    context 'with new config (single inverter)' do
      let(:powers) do
        {
          inverter_power: 3000,
          grid_import_power: 500,
          battery_discharging_power: 200,
          battery_charging_power: 100,
          grid_export_power: 400,
          wallbox_power: 600,
          heatpump_power: 300,
        }
      end

      it 'uses total' do
        result = described_class.calculate(**powers)
        incoming = 3000 + 500 + 200
        outgoing = 100 + 400 + 600 + 300
        expect(result).to eq(incoming - outgoing)
      end
    end

    context 'with new config (multiple inverters)' do
      let(:powers) do
        {
          inverter_power_1: 1500,
          inverter_power_2: 1500,
          grid_import_power: 500,
          battery_discharging_power: 200,
          battery_charging_power: 100,
          grid_export_power: 400,
          wallbox_power: 600,
          heatpump_power: 300,
        }
      end

      it 'sums up parts' do
        result = described_class.calculate(**powers)
        incoming = 1500 + 1500 + 500 + 200
        outgoing = 100 + 400 + 600 + 300
        expect(result).to eq(incoming - outgoing)
      end
    end

    context 'with new config (multiple inverters with total)' do
      let(:powers) do
        {
          inverter_power: 3000,
          inverter_power_1: 1501,
          inverter_power_2: 1502,
          grid_import_power: 500,
          battery_discharging_power: 200,
          battery_charging_power: 100,
          grid_export_power: 400,
          wallbox_power: 600,
          heatpump_power: 300,
        }
      end

      it 'uses total and ignores the parts' do
        result = described_class.calculate(**powers)
        incoming = 3000 + 500 + 200
        outgoing = 100 + 400 + 600 + 300
        expect(result).to eq(incoming - outgoing)
      end
    end
  end
end
