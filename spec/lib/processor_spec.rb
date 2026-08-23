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
          max_age: 1_000_000_000,
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

    # House power holds for one point in time, so every sensor of that
    # timestamp shares one calculation. Calculating per line repeated the same
    # work once per sensor and queued the same result as often.
    context 'when a batch carries several sensors per timestamp' do
      subject(:run) { processor.run(lines) }

      let(:lines) do
        [
          'SENEC inverter_power=500.0 1000000000',
          'SENEC grid_power_plus=100.0 1000000000',
          'SENEC bat_power_plus=200.0 1000000000',
          'SENEC inverter_power=600.0 2000000000',
          'SENEC grid_power_plus=150.0 2000000000',
        ]
      end

      before do
        allow(HousePowerCalculator).to receive(:new).and_return(house_calc)
      end

      def house_calc
        @house_calc ||= instance_spy(HousePowerCalculator)
      end

      it 'recalculates once per timestamp' do
        run

        expect(house_calc).to have_received(:recalculate).twice
        expect(house_calc).to have_received(:recalculate).with(
          timestamp: 1_000_000_000,
        ).once
        expect(house_calc).to have_received(:recalculate).with(
          timestamp: 2_000_000_000,
        ).once
      end

      # The calculation reads the samples of the batch, so it must run after
      # every line of the batch is stored.
      it 'recalculates after the batch is stored' do
        allow(house_calc).to receive(:recalculate) do
          expect(Incoming.count).to eq(lines.size)
        end

        run

        expect(house_calc).to have_received(:recalculate).twice
      end
    end

    context 'when a relevant line carries no timestamp' do
      subject(:run) { processor.run(['SENEC inverter_power=500.0']) }

      let(:house_calc) { instance_spy(HousePowerCalculator) }

      before do
        allow(HousePowerCalculator).to receive(:new).and_return(house_calc)
      end

      # The line is stored under the time of the request, so the calculation
      # uses that same time.
      it 'recalculates for the stored timestamp' do
        run

        expect(house_calc).to have_received(:recalculate).with(
          timestamp: Incoming.last.timestamp,
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
          max_age: 1_000_000_000,
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
          max_age: 1_000_000_000,
        )
        expect(cache).to be_nil
      end
    end

    context 'when a line is malformed' do
      subject(:run) { processor.run(lines) }

      let(:lines) do
        ['SENEC inverter_power=abc 1000000000', 'SENEC inverter_power=500.0 2000000000']
      end

      it 'does not raise' do
        expect { run }.not_to raise_error
      end

      it 'stores the valid line only' do
        expect { run }.to change(Incoming, :count).by(1)

        expect(Incoming.last.timestamp).to eq(2_000_000_000)
      end

      it 'queues the valid line only' do
        expect { run }.to change(Outgoing, :count).by(1)

        expect(Outgoing.last.line_protocol).to eq(lines.last)
      end

      it 'counts the skipped line' do
        run

        expect(Stats.counter(LineBatch::SKIPPED_STAT)).to eq(1)
      end
    end

    # The write route answers 400 for this, and the client reads that as
    # "nothing was stored". So the batch must store nothing at all, or the
    # retry writes a stored line a second time.
    context 'when every line is malformed' do
      subject(:run) { processor.run(lines) }

      let(:lines) do
        ['SENEC inverter_power=abc 1000000000', 'SENEC inverter_power= 2000000000']
      end

      def attempt
        run
      rescue LineProtocolParser::InvalidLineProtocolError
        nil
      end

      it 'raises' do
        expect { run }.to raise_error(LineProtocolParser::InvalidLineProtocolError)
      end

      it 'stores no incoming row' do
        expect { attempt }.not_to change(Incoming, :count)
      end

      it 'queues no outgoing line' do
        expect { attempt }.not_to change(Outgoing, :count)
      end
    end

    # The write route answers 500 for a database error, and the client retries
    # the full batch. So the batch must store nothing at all, or the retry
    # writes the lines before the error a second time.
    context 'when the database fails in the middle of the batch' do
      subject(:run) { processor.run(lines) }

      let(:lines) do
        ['SENEC inverter_power=500.0 1000000000', 'SENEC inverter_power=600.0 2000000000']
      end

      before do
        calls = 0

        allow(Incoming).to receive(:insert_all!).and_wrap_original do |original, *args|
          calls += 1
          raise ActiveRecord::StatementInvalid, 'Boom!' if calls == 2

          original.call(*args)
        end
      end

      def attempt
        run
      rescue ActiveRecord::StatementInvalid
        nil
      end

      it 'raises' do
        expect { run }.to raise_error(ActiveRecord::StatementInvalid)
      end

      it 'stores no incoming row' do
        expect { attempt }.not_to change(Incoming, :count)
      end

      it 'queues no outgoing line' do
        expect { attempt }.not_to change(Outgoing, :count)
      end

      it 'creates no target' do
        expect { attempt }.not_to change(Target, :count)
      end

      it 'does not notify the outbox' do
        allow(OutboxNotifier).to receive(:notify!)

        attempt

        expect(OutboxNotifier).not_to have_received(:notify!)
      end
    end

    context 'when a line is blank' do
      subject(:run) { processor.run(lines) }

      let(:lines) { ["\n", 'SENEC inverter_power=500.0 1000000000'] }

      it 'stores the other line' do
        expect { run }.to change(Incoming, :count).by(1)
      end

      it 'does not count the blank line as skipped' do
        run

        expect(Stats.counter(LineBatch::SKIPPED_STAT)).to be_zero
      end
    end

    context 'without any parsable line' do
      subject(:run) { processor.run(['   ']) }

      it 'stores nothing' do
        expect { run }.not_to change(Incoming, :count)
      end

      it 'does not create a target' do
        expect { run }.not_to change(Target, :count)
      end
    end
  end

  describe '#value_columns' do
    it 'rejects a value type the database has no column for' do
      expect { processor.send(:value_columns, [1, 2]) }.to raise_error(
        ArgumentError,
        /Unsupported value type: Array/,
      )
    end
  end
end
