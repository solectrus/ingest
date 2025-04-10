describe SensorValueCache do
  subject(:cache) { described_class.instance }

  let(:measurement) { 'SENEC' }
  let(:field) { 'inverter_power' }

  before { cache.reset! }

  describe '#write and #read' do
    it 'stores and retrieves a value if timestamp is valid' do
      cache.write(measurement:, field:, timestamp: 100, value: 42)

      result = cache.read(measurement:, field:, max_timestamp: 100)
      expect(result).to eq({ timestamp: 100, value: 42 })
    end

    it 'does not return a value if timestamp is too new' do
      cache.write(measurement:, field:, timestamp: 200, value: 99)

      result = cache.read(measurement:, field:, max_timestamp: 100)
      expect(result).to be_nil
    end

    it 'rejects older write if newer timestamp already exists' do
      cache.write(measurement:, field:, timestamp: 200, value: 99)
      cache.write(measurement:, field:, timestamp: 100, value: 42)

      result = cache.read(measurement:, field:, max_timestamp: 300)
      expect(result).to eq({ timestamp: 200, value: 99 })
    end

    it 'overwrites older value if timestamp is newer' do
      cache.write(measurement:, field:, timestamp: 100, value: 1)
      cache.write(measurement:, field:, timestamp: 200, value: 2)

      result = cache.read(measurement:, field:, max_timestamp: 300)
      expect(result).to eq({ timestamp: 200, value: 2 })
    end
  end

  describe '#reset!' do
    it 'clears the cache' do
      cache.write(measurement:, field:, timestamp: 100, value: 42)
      expect(cache.read(measurement:, field:, max_timestamp: 100)).to be_present

      cache.reset!
      expect(cache.read(measurement:, field:, max_timestamp: 100)).to be_nil
    end
  end

  describe '#stats' do
    before do
      cache.write(measurement:, field:, timestamp: 100, value: 42)
      cache.write(measurement:, field:, timestamp: 200, value: 99)
      cache.write(measurement:, field: 'other_field', timestamp: 199, value: 98)
      cache.write(measurement: 'other_measurement', field:, timestamp: 198, value: 97)
    end

    it 'returns the correct stats' do
      stats = cache.stats
      expect(stats[:size]).to eq(3)
      expect(stats[:oldest_timestamp]).to eq(198)
      expect(stats[:newest_timestamp]).to eq(200)
    end

    it 'returns empty stats when cache is empty' do
      cache.reset!

      stats = cache.stats
      expect(stats[:size]).to eq(0)
      expect(stats[:oldest_timestamp]).to be_nil
      expect(stats[:newest_timestamp]).to be_nil
    end
  end
end
