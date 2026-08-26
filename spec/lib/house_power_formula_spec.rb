describe HousePowerFormula do
  describe '.calculate' do
    context 'with an unknown sensor' do
      it 'raises ArgumentError' do
        expect do
          described_class.calculate(inverter_power: 3000, unknown_power: 1)
        end.to raise_error(ArgumentError, /Unknown keys: unknown_power/)
      end
    end

    context 'without incoming sensors' do
      it 'returns nil' do
        expect(described_class.calculate(grid_export_power: 400)).to be_nil
      end
    end

    context 'without outgoing sensors' do
      it 'returns nil' do
        expect(described_class.calculate(inverter_power: 3000)).to be_nil
      end
    end

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

  describe '.terms' do
    let(:powers) do
      {
        inverter_power: 3000,
        grid_import_power: 500,
        battery_charging_power: 100,
      }
    end

    it 'names every sensor it uses, in the order it adds them' do
      expect(described_class.terms(**powers).map(&:key)).to eq(
        %i[inverter_power grid_import_power battery_charging_power],
      )
    end

    it 'adds an incoming sensor and subtracts an outgoing one' do
      terms = described_class.terms(**powers).to_h { [it.key, it.signed_value] }

      expect(terms).to eq(
        inverter_power: 3000,
        grid_import_power: 500,
        battery_charging_power: -100,
      )
    end

    # The page prints these terms. If it printed a part while the formula used
    # the total, a reader would add up numbers that Ingest never added.
    it 'leaves out the parts while the total is there' do
      keys =
        described_class
          .terms(**powers, inverter_power_1: 1500, inverter_power_2: 1500)
          .map(&:key)

      expect(keys).to eq(
        %i[inverter_power grid_import_power battery_charging_power],
      )
    end

    it 'is empty without an incoming sensor' do
      expect(described_class.terms(grid_export_power: 400)).to be_empty
    end

    it 'is empty without an outgoing sensor' do
      expect(described_class.terms(inverter_power: 3000)).to be_empty
    end
  end

  describe '.sum' do
    it 'adds the terms of a calculation' do
      terms = described_class.terms(inverter_power: 3000, grid_export_power: 400)

      expect(described_class.sum(terms)).to eq(2600)
    end

    # A house cannot give power back.
    it 'cuts a negative sum at zero' do
      terms = described_class.terms(inverter_power: 100, grid_export_power: 400)

      expect(described_class.sum(terms)).to eq(0)
    end

    it 'answers nothing for no term' do
      expect(described_class.sum([])).to be_nil
    end
  end

  # The page prints the formula before a calculation has run, and it then has
  # only the keys of the configuration.
  describe '.terms_for' do
    it 'signs every key without a value behind it' do
      terms = described_class.terms_for(%i[inverter_power grid_export_power])

      expect(terms.map { [it.key, it.sign] }).to eq(
        [[:inverter_power, 1], [:grid_export_power, -1]],
      )
      expect(terms.map(&:value)).to all(be_zero)
    end

    it 'is empty for a configuration that cannot produce a house power' do
      expect(described_class.terms_for(%i[inverter_power])).to be_empty
    end
  end
end
