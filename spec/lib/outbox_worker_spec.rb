describe OutboxWorker do
  let(:target) do
    Target.create!(
      influx_token: 'test-token',
      bucket: 'test-bucket',
      org: 'test-org',
      precision: InfluxDB2::WritePrecision::NANOSECOND,
    )
  end

  before do
    target.outgoings.create!(line_protocol: 'measurement1 field=1 1000')
    target.outgoings.create!(line_protocol: 'measurement2 field=2 1000')
    target.outgoings.create!(line_protocol: 'measurement3 field=3 2000')
  end

  describe '.run_once' do
    context 'when all writes succeed' do
      before { allow(InfluxWriter).to receive(:write).and_return(true) }

      it 'writes batches to InfluxWriter and deletes all outgoings' do
        expect do
          processed = described_class.run_once
          expect(processed).to eq(3)
        end.to change(Outgoing, :count).by(-3)
      end
    end

    context 'when a permanent write fails (ClientError)' do
      before do
        # Default write is OK
        allow(InfluxWriter).to receive(:write).and_return(true)

        # Simulate error for timestamp = 1000
        allow(InfluxWriter).to receive(:write).with(
          a_collection_including(
            'measurement1 field=1 1000',
            'measurement2 field=2 1000',
          ),
          anything,
        ).and_raise(InfluxWriter::ClientError.new('invalid token'))
      end

      it 'deletes only permanently failed and successfully written outgoings' do
        expect do
          processed = described_class.run_once
          expect(processed).to eq(1) # only timestamp=2000 counts
        end.to change(Outgoing, :count).by(-3)

        expect(Outgoing.pluck(:line_protocol)).to be_empty
      end
    end

    context 'when a temporary write fails (ServerError)' do
      before do
        # Default write ist OK
        allow(InfluxWriter).to receive(:write).and_return(true)

        # Simulate error for timestamp = 1000
        allow(InfluxWriter).to receive(:write).with(
          a_collection_including(
            'measurement1 field=1 1000',
            'measurement2 field=2 1000',
          ),
          anything,
        ).and_raise(InfluxWriter::ServerError.new('Influx down'))
      end

      it 'keeps outgoings that failed temporarily and deletes successful ones' do
        expect do
          processed = described_class.run_once
          expect(processed).to eq(1) # only timestamp=2000 counts
        end.to change(Outgoing, :count).by(-1)

        expect(Outgoing.pluck(:line_protocol)).to contain_exactly(
          'measurement1 field=1 1000',
          'measurement2 field=2 1000',
        )
      end
    end
  end

  describe '.run_loop' do
    before do
      allow(described_class).to receive(:run_once).and_return(0)
      allow(described_class).to receive(:sleep) # Stub sleep to avoid waiting
    end

    it 'runs repeatedly using run_once and sleep' do
      thread = Thread.new { described_class.run_loop }

      sleep 0.1
      thread.kill
      thread.join

      expect(described_class).to have_received(:run_once).at_least(:once)
      expect(described_class).to have_received(:sleep).at_least(:once)
    end
  end
end
