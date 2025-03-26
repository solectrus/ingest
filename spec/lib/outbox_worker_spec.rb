describe OutboxWorker do
  let(:target) do
    Target.create!(
      influx_token: 'test-token',
      bucket: 'test-bucket',
      org: 'test-org',
      precision: 'ns',
    )
  end

  before do
    target.outgoings.create!(line_protocol: 'measurement1 field=1 1000')
    target.outgoings.create!(line_protocol: 'measurement2 field=2 1000')
    target.outgoings.create!(line_protocol: 'measurement3 field=3 2000')

    allow(InfluxWriter).to receive(:write).and_return(true)
  end

  describe '.run_once' do
    it 'writes batches to InfluxWriter' do
      described_class.run_once

      expect(InfluxWriter).to have_received(:write).twice

      # timestamp = 1000 => 2 entries
      expect(InfluxWriter).to have_received(:write).with(
        a_collection_including(
          'measurement1 field=1 1000',
          'measurement2 field=2 1000',
        ),
        influx_token: target.influx_token,
        bucket: target.bucket,
        org: target.org,
        precision: target.precision,
      )

      # timestamp = 2000 => 1 entry
      expect(InfluxWriter).to have_received(:write).with(
        a_collection_including('measurement3 field=3 2000'),
        influx_token: target.influx_token,
        bucket: target.bucket,
        org: target.org,
        precision: target.precision,
      )
    end

    it 'removes outgoings after processing' do
      expect do
        processed = described_class.run_once
        expect(processed).to eq(3)
      end.to change(Outgoing, :count).by(-3)
    end
  end

  describe '.run_loop' do
    before do
      allow(described_class).to receive(:run_once).and_return(0)
      allow(described_class).to receive(:sleep) # Stub sleep to avoid waiting
    end

    it 'runs loop and calls run_once repeatedly' do
      thread = Thread.new { described_class.run_loop }

      sleep 0.1
      thread.kill
      thread.join

      expect(described_class).to have_received(:run_once).at_least(:once)
      expect(described_class).to have_received(:sleep).at_least(:once)
    end
  end
end
