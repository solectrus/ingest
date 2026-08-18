describe CleanupWorker do
  let!(:old_entry) do
    target.incomings.create!(
      measurement: 'SENEC',
      field: 'test',
      value: 42,
      created_at: 13.hours.ago, # Older than 12 hours (default)
    )
  end

  let!(:recent_entry) do
    target.incomings.create!(
      measurement: 'SENEC',
      field: 'test',
      value: 42,
      created_at: 5.hours.ago, # Within the 12-hour retention period (default)
    )
  end

  let(:target) do
    Target.create!(influx_token: 'foo', bucket: 'test', org: 'test')
  end

  describe '.run' do
    context 'when the database works' do
      before { described_class.run }

      it 'deletes old entries' do
        expect(Incoming.exists?(old_entry.id)).to be false
      end

      it 'does not delete recent entries' do
        expect(Incoming.exists?(recent_entry.id)).to be true
      end
    end

    context 'when the database fails' do
      before do
        allow(Database).to receive(:thread_safe_write).and_raise(
          ActiveRecord::StatementInvalid,
          'database is locked',
        )
      end

      it 'reports the error and does not raise' do
        expect { described_class.run }.not_to raise_error
      end

      it 'keeps the entries' do
        expect { described_class.run }.not_to change(Incoming, :count)
      end
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
