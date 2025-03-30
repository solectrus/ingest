describe SensorEnvConfig do
  before do
    described_class.instance_variable_set(:@config, nil)
    described_class.instance_variable_set(:@exclude_from_house_power_keys, nil)
    described_class.instance_variable_set(:@sensor_keys_for_house_power, nil)
    described_class.instance_variable_set(:@house_power_destination, nil)
  end

  describe '.house_power_calculated' do
    subject { described_class.house_power_calculated }

    context 'when ENV is not set or empty' do
      before { ENV['INFLUX_SENSOR_HOUSE_POWER_CALCULATED'] = '' }

      it { is_expected.to be_nil }
    end

    context 'when ENV is set' do
      before do
        ENV['INFLUX_SENSOR_HOUSE_POWER_CALCULATED'] = 'Calc:house_power'
      end

      it { is_expected.to eq(measurement: 'Calc', field: 'house_power') }
    end
  end

  describe '.house_power_destination' do
    subject { described_class.house_power_destination }

    context 'when calculated is set' do
      before do
        ENV['INFLUX_SENSOR_HOUSE_POWER_CALCULATED'] = 'Calc:house_power'
        ENV['INFLUX_SENSOR_HOUSE_POWER'] = 'SENEC:house_power'
      end

      it { is_expected.to eq(measurement: 'Calc', field: 'house_power') }
    end

    context 'when calculated is not set' do
      before do
        ENV['INFLUX_SENSOR_HOUSE_POWER_CALCULATED'] = ''
        ENV['INFLUX_SENSOR_HOUSE_POWER'] = 'SENEC:house_power'
      end

      it { is_expected.to eq(measurement: 'SENEC', field: 'house_power') }
    end
  end

  describe '.exclude_from_house_power_keys' do
    subject { described_class.exclude_from_house_power_keys }

    before do
      ENV['INFLUX_EXCLUDE_FROM_HOUSE_POWER'] = 'WALLBOX_POWER, HEATPUMP_POWER'
    end

    it { is_expected.to eq(Set[:wallbox_power, :heatpump_power]) }
  end

  describe '.sensor_keys_for_house_power' do
    subject { described_class.sensor_keys_for_house_power }

    before { ENV['INFLUX_EXCLUDE_FROM_HOUSE_POWER'] = 'HEATPUMP_POWER' }

    it { is_expected.not_to include(:house_power) }
    it { is_expected.not_to include(:heatpump_power) }
    it { is_expected.to include(:inverter_power) }
  end

  describe '.relevant_for_house_power?' do
    subject { described_class.relevant_for_house_power?(point) }

    context 'when relevant' do
      let(:point) do
        instance_double(Point, name: 'SENEC', fields: { 'inverter_power' => 1 })
      end

      it { is_expected.to be(true) }
    end

    context 'when not relevant (field mismatch)' do
      let(:point) do
        instance_double(Point, name: 'SENEC', fields: { 'something_else' => 1 })
      end

      it { is_expected.to be(false) }
    end

    context 'when not relevant (measurement mismatch)' do
      let(:point) do
        instance_double(Point, name: 'OTHER', fields: { 'inverter_power' => 1 })
      end

      it { is_expected.to be(false) }
    end
  end

  describe '.config' do
    subject(:config) { described_class.config }

    it 'parses configured sensors from ENV' do
      expect(config[:inverter_power]).to eq(
        measurement: 'SENEC',
        field: 'inverter_power',
      )
      expect(config[:heatpump_power]).to eq(
        measurement: 'Heatpump',
        field: 'power',
      )
      expect(config[:house_power]).to eq(
        measurement: 'SENEC',
        field: 'house_power',
      )
    end

    it 'ignores unset or empty ENV variables' do
      expect(config).not_to have_key(:balcony_inverter_power)
    end
  end
end
