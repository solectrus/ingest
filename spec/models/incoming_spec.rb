describe Incoming do
  subject(:incoming) do
    described_class.new(
      target: target,
      measurement: 'SENEC',
      field: 'inverter_power',
      timestamp: 1000,
    )
  end

  let(:target) do
    Target.create!(
      influx_token: 'test-token',
      bucket: 'test-bucket',
      org: 'test-org',
      precision: InfluxDB2::WritePrecision::NANOSECOND,
    )
  end

  describe 'validations' do
    it 'validates presence of measurement' do
      incoming.measurement = nil
      expect(incoming).not_to be_valid
      expect(incoming.errors[:measurement]).to include("can't be blank")
    end

    it 'validates presence of field' do
      incoming.field = nil
      expect(incoming).not_to be_valid
      expect(incoming.errors[:field]).to include("can't be blank")
    end

    it 'sets timestamp to default if missing' do
      incoming.timestamp = nil
      incoming.valid?
      expect(incoming.timestamp).to be_present
    end
  end

  describe '#value=' do
    it 'sets the correct field when Integer' do
      incoming.value = 42
      expect(incoming.value_int).to eq(42)
    end

    it 'sets the correct field when Float' do
      incoming.value = 42.5
      expect(incoming.value_float).to eq(42.5)
    end

    it 'sets the correct field when TrueClass' do
      incoming.value = true
      expect(incoming.value_bool).to be(true)
    end

    it 'sets the correct field when FalseClass' do
      incoming.value = false
      expect(incoming.value_bool).to be(false)
    end

    it 'sets the correct field when String' do
      incoming.value = 'test'
      expect(incoming.value_string).to eq('test')
    end

    it 'adds an error if the value type is invalid' do
      incoming.value = nil

      expect(incoming).not_to be_valid
      expect(incoming.errors[:value]).to include("can't be blank")
    end
  end

  describe '#value' do
    it 'returns the value_int when Integer' do
      incoming.value_int = 42
      expect(incoming.value).to eq(42)
    end

    it 'returns the value_float when Float' do
      incoming.value_float = 42.5
      expect(incoming.value).to eq(42.5)
    end

    it 'returns the value_string when String' do
      incoming.value_string = 'test'
      expect(incoming.value).to eq('test')
    end

    it 'returns the value_bool when TrueClass or FalseClass' do
      incoming.value_bool = true
      expect(incoming.value).to be(true)
    end
  end
end
