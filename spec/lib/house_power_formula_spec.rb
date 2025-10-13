describe HousePowerFormula do
  describe '.calculate' do
    context 'with single inverter' do
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

    context 'with multiple inverters' do
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

    context 'with multiple inverters containing total' do
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
