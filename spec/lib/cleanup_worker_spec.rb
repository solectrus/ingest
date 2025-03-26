describe CleanupWorker do
  let!(:old_entry) do
    Incoming.create!(
      target:,
      measurement: 'SENEC',
      field: 'test',
      value: 42,
      timestamp: 25.hours.ago.to_i * 1_000_000_000,
    )
  end

  let!(:recent_entry) do
    Incoming.create!(
      target:,
      measurement: 'SENEC',
      field: 'test',
      value: 42,
      timestamp: 5.hours.ago.to_i * 1_000_000_000,
    )
  end

  let(:target) do
    Target.create!(
      influx_token: 'foo',
      bucket: 'test',
      org: 'test',
      precision: 'ns',
    )
  end

  describe '.run' do
    before { described_class.run }

    it 'deletes old entries' do
      expect(Incoming.exists?(old_entry.id)).to be false
    end

    it 'does not delete recent entries' do
      expect(Incoming.exists?(recent_entry.id)).to be true
    end
  end
end
