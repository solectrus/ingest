describe CleanupWorker do
  let!(:old_entry) do
    Incoming.create!(
      target:,
      measurement: 'SENEC',
      field: 'test',
      value: 42,
      timestamp: 1000,
      created_at: 25.hours.ago,
    )
  end

  let!(:recent_entry) do
    Incoming.create!(
      target:,
      measurement: 'SENEC',
      field: 'test',
      value: 42,
      timestamp: 1001,
      created_at: 5.hours.ago,
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

  describe '.run_loop' do
    it 'calls .run repeatedly and sleeps in between' do
      allow(described_class).to receive(:sleep) # Stub sleep to avoid waiting

      call_count = 0
      allow(described_class).to receive(:run) do
        call_count += 1
        raise 'STOP' if call_count >= 3
      end

      expect do
        described_class.run_loop
      rescue StandardError => e
        raise unless e.message == 'STOP'
      end.not_to raise_error

      expect(described_class).to have_received(:run).at_least(3).times
    end
  end
end
