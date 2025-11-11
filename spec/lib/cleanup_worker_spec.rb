describe CleanupWorker do
  let!(:old_entry) do
    target.incomings.create!(
      measurement: 'SENEC',
      field: 'test',
      value: 42,
      created_at: 37.hours.ago, # Older than 36 hours
    )
  end

  let!(:recent_entry) do
    target.incomings.create!(
      measurement: 'SENEC',
      field: 'test',
      value: 42,
      created_at: 20.hours.ago, # Within the 36-hour retention period
    )
  end

  let(:target) do
    Target.create!(influx_token: 'foo', bucket: 'test', org: 'test')
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
