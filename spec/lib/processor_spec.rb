describe Processor do
  subject(:processor) do
    described_class.new(influx_token:, bucket:, org:, precision:)
  end

  let(:influx_token) { 'test-token' }
  let(:bucket) { 'test-bucket' }
  let(:org) { 'test-org' }
  let(:precision) { InfluxDB2::WritePrecision::NANOSECOND }

  describe '#run' do
    subject(:run) { processor.run([line]) }

    context 'when line contains inverter_power only' do
      let(:line) { 'SENEC inverter_power=500.0 1000000000' }

      it 'creates a target if it does not exist' do
        expect { run }.to change(Target, :count).by(1)

        target = Target.last
        expect(target.influx_token).to eq(influx_token)
        expect(target.bucket).to eq(bucket)
        expect(target.org).to eq(org)
        expect(target.precision).to eq(precision)
      end

      it 'stores the incoming data' do
        expect { run }.to change(Incoming, :count).by(1)

        incoming = Incoming.last
        expect(incoming.measurement).to eq('SENEC')
        expect(incoming.field).to eq('inverter_power')
        expect(incoming.value).to eq(500.0)
        expect(incoming.timestamp).to eq(1_000_000_000)
      end

      it 'caches the incoming data' do
        run

        cache = SensorValueCache.instance.read(
          measurement: 'SENEC',
          field: 'inverter_power',
          max_timestamp: 1_000_000_000,
        )
        expect(cache).to eq(
          {
            timestamp: 1_000_000_000,
            value: 500.0,
          },
        )
      end

      it 'queues the outgoing line' do
        expect { run }.to change(Outgoing, :count).by(1)

        outgoing = Outgoing.last
        expect(outgoing.line_protocol).to eq(line)
      end

      it 'triggers house power recalculation if relevant' do
        allow(SensorEnvConfig).to receive(
          :relevant_for_house_power?,
        ).and_return(true)

        house_calc = instance_spy(HousePowerCalculator)
        allow(HousePowerCalculator).to receive(:new).and_return(house_calc)

        run

        expect(house_calc).to have_received(:recalculate).with(
          timestamp: 1_000_000_000,
        )
      end
    end

    context 'when line contains house_power and others' do
      let(:line) { 'SENEC house_power=300i,grid_power_plus=500i 1000000000' }

      it 'filters out house_power field when enqueuing outgoing' do
        run

        outgoing = Outgoing.last
        expect(outgoing.line_protocol).to eq(
          'SENEC grid_power_plus=500i 1000000000',
        )
      end
    end

    context 'when line contains house_power only' do
      let(:line) { 'SENEC house_power=300i 1000000000' }

      it 'skips enqueue if only house_power is present' do
        expect { run }.not_to change(Outgoing, :count)
      end
    end

    context 'when line contains boolean value' do
      let(:line) { 'SENEC system_status_ok=true 1000000000' }

      it 'stores the incoming data' do
        expect { run }.to change(Incoming, :count).by(1)

        incoming = Incoming.last
        expect(incoming.measurement).to eq('SENEC')
        expect(incoming.field).to eq('system_status_ok')
        expect(incoming.value).to be(true)
        expect(incoming.timestamp).to eq(1_000_000_000)
      end

      it 'does not cache the incoming data' do
        run

        cache = SensorValueCache.instance.read(
          measurement: 'SENEC',
          field: 'system_status_ok',
          max_timestamp: 1_000_000_000,
        )
        expect(cache).to be_nil
      end
    end

    context 'when line contains string value' do
      let(:line) { 'SENEC system_status="It\'s all fine" 1000000000' }

      it 'stores the incoming data' do
        expect { run }.to change(Incoming, :count).by(1)

        incoming = Incoming.last
        expect(incoming.measurement).to eq('SENEC')
        expect(incoming.field).to eq('system_status')
        expect(incoming.value).to eq("It's all fine")
        expect(incoming.timestamp).to eq(1_000_000_000)
      end

      it 'does not cache the incoming data' do
        run

        cache = SensorValueCache.instance.read(
          measurement: 'SENEC',
          field: 'system_status',
          max_timestamp: 1_000_000_000,
        )
        expect(cache).to be_nil
      end
    end
  end
end
