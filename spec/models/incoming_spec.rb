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

    it 'validates presence of value' do
      incoming.value = nil
      expect(incoming).not_to be_valid
      expect(incoming.errors[:value]).to include("can't be blank")
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
      expect(incoming).to be_valid
      expect(incoming.value_int).to eq(42)
    end

    it 'sets the correct field when Float' do
      incoming.value = 42.5
      expect(incoming).to be_valid
      expect(incoming.value_float).to eq(42.5)
    end

    it 'sets the correct field when TrueClass' do
      incoming.value = true
      expect(incoming).to be_valid
      expect(incoming.value_bool).to be(true)
    end

    it 'sets the correct field when FalseClass' do
      incoming.value = false
      expect(incoming).to be_valid
      expect(incoming.value_bool).to be(false)
    end

    it 'sets the correct field when String' do
      incoming.value = 'test'
      expect(incoming).to be_valid
      expect(incoming.value_string).to eq('test')
    end

    it 'fails if the value type is invalid' do
      expect do
        incoming.value = { invalid: 'type' }
      end.to raise_error(ArgumentError, 'Unsupported value type: Hash')
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

    it 'returns the value_bool when TrueClass' do
      incoming.value_bool = true
      expect(incoming.value).to be(true)
    end

    it 'returns the value_bool when FalseClass' do
      incoming.value_bool = false
      expect(incoming.value).to be(false)
    end
  end

  describe 'cache writing' do
    let(:cache) { SensorValueCache.instance }

    it 'writes to the cache after creation' do
      cache.reset!

      described_class.create!(
        target:,
        measurement: 'SENEC',
        field: 'inverter_power',
        timestamp: 1000,
        value: 42,
      )

      expect(
        cache.read(
          measurement: 'SENEC',
          field: 'inverter_power',
          max_timestamp: target.timestamp_ns(1000),
        ),
      ).to include(value: 42)
    end

    it 'does not cache string values' do
      cache.reset!

      described_class.create!(
        target:,
        measurement: 'SENEC',
        field: 'system_status',
        timestamp: 1000,
        value: 'It\'s all fine',
      )

      expect(
        cache.read(
          measurement: 'SENEC',
          field: 'system_status',
          max_timestamp: target.timestamp_ns(1000),
        ),
      ).to be_nil
    end

    it 'does not cache boolean values' do
      cache.reset!

      described_class.create!(
        target:,
        measurement: 'SENEC',
        field: 'system_status_ok',
        timestamp: 1000,
        value: true,
      )

      expect(
        cache.read(
          measurement: 'SENEC',
          field: 'system_status_ok',
          max_timestamp: target.timestamp_ns(1000),
        ),
      ).to be_nil
    end
  end
end
