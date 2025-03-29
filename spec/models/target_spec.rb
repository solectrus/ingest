describe Target do
  subject(:target) do
    described_class.create!(
      influx_token: 'test-token',
      bucket: 'test-bucket',
      org: 'test-org',
      precision: InfluxDB2::WritePrecision::MILLISECOND,
    )
  end

  describe 'validations' do
    it 'is valid with valid attributes' do
      expect(target).to be_valid
    end

    it 'is invalid without influx_token' do
      target.influx_token = nil
      expect(target).not_to be_valid
    end

    it 'is invalid without bucket' do
      target.bucket = nil
      expect(target).not_to be_valid
    end

    it 'is invalid without org' do
      target.org = nil
      expect(target).not_to be_valid
    end

    it 'is invalid without precision' do
      target.precision = nil
      expect(target).not_to be_valid
    end
  end

  describe '#timestamp_ns' do
    it 'converts timestamp correctly based on precision' do
      expect(target.timestamp_ns(1_000)).to eq(1_000 * 1_000_000)
    end
  end

  describe '#timestamp' do
    it 'converts ns timestamp back based on precision' do
      expect(target.timestamp(1_000_000_000)).to eq(1_000)
    end
  end
end
