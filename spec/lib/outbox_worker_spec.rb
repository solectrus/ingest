describe OutboxWorker do
  # Counts the SELECTs on the targets table of a block.
  def target_queries
    count = 0
    subscriber =
      ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
        count += 1 if payload[:sql].include?('"targets"')
      end
    yield
    count
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  let(:target) do
    Target.create!(
      influx_token: 'test-token',
      bucket: 'test-bucket',
      org: 'test-org',
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

      # Line protocol carries the timestamp per line, so one request holds the
      # lines of every timestamp. One request per timestamp made a backlog need
      # as many connections as the collector had polls.
      it 'sends the lines of all timestamps in one request' do
        described_class.run_once

        expect(InfluxWriter).to have_received(:write).once.with(
          [
            'measurement1 field=1 1000',
            'measurement2 field=2 1000',
            'measurement3 field=3 2000',
          ],
          anything,
        )
      end

      # The target was read per group before, so a backlog of many timestamps
      # ran one SELECT per timestamp.
      it 'loads the target of a batch once' do
        expect(target_queries { described_class.run_once }).to eq(1)
      end
    end

    context 'with two targets' do
      let(:other_target) do
        Target.create!(
          influx_token: 'other-token',
          bucket: 'other-bucket',
          org: 'other-org',
        )
      end

      before do
        other_target.outgoings.create!(line_protocol: 'measurement4 field=4 1000')
        allow(InfluxWriter).to receive(:write).and_return(true)
      end

      it 'sends one request per target' do
        described_class.run_once

        expect(InfluxWriter).to have_received(:write).twice
        expect(InfluxWriter).to have_received(:write).with(
          ['measurement4 field=4 1000'],
          hash_including(influx_token: 'other-token'),
        )
      end
    end

    context 'when a permanent write fails (ClientError)' do
      before do
        allow(InfluxWriter).to receive(:write).and_raise(
          InfluxWriter::ClientError.new('invalid token'),
        )
      end

      it 'deletes the outgoings it cannot ever write' do
        expect do
          processed = described_class.run_once
          expect(processed).to eq(0)
        end.to change(Outgoing, :count).by(-3)

        expect(Outgoing.pluck(:line_protocol)).to be_empty
      end
    end

    # A 400 says InfluxDB wrote no point of the request, so dropping the batch
    # threw away up to 500 good lines for one bad one.
    context 'when one line of a batch cannot be parsed (400)' do
      let(:bad) { 'measurement2 field=2 1000' }

      before do
        allow(InfluxWriter).to receive(:write) do |lines, **|
          raise InfluxWriter::ClientError.new('unable to parse', 400) if lines.include?(bad)

          true
        end
      end

      it 'drops the refused line only' do
        expect { described_class.run_once }.to change(Outgoing, :count).by(-3)

        expect(InfluxWriter).to have_received(:write).with([bad], any_args)
      end

      it 'writes the good lines of the same batch' do
        described_class.run_once

        written = []
        expect(InfluxWriter).to have_received(:write).at_least(:once) do |lines, **|
          written.concat(lines)
        end

        expect(written).to include('measurement1 field=1 1000')
        expect(written).to include('measurement3 field=3 2000')
      end

      it 'counts the good lines only' do
        expect(described_class.run_once).to eq(2)
      end
    end

    context 'when every line of a batch cannot be parsed (400)' do
      before do
        allow(InfluxWriter).to receive(:write).and_raise(
          InfluxWriter::ClientError.new('unable to parse', 400),
        )
      end

      it 'drops them all and counts none' do
        expect { expect(described_class.run_once).to eq(0) }.to change(
          Outgoing,
          :count,
        ).by(-3)
      end
    end

    context 'when InfluxDB goes away after part of a split batch went out' do
      before do
        calls = 0
        allow(InfluxWriter).to receive(:write) do
          calls += 1
          raise InfluxWriter::ClientError.new('unable to parse', 400) if calls == 1
          raise InfluxWriter::ServerError, 'gone' if calls > 2

          true
        end
      end

      it 'keeps what did not go out and drops nothing' do
        expect { described_class.run_once }.to change(Outgoing, :count).by(-1)

        expect(Outgoing.count).to eq(2)
      end
    end

    # Splitting must not run into one timeout per half.
    context 'when InfluxDB goes away while a batch is being split' do
      before do
        calls = 0
        allow(InfluxWriter).to receive(:write) do
          calls += 1
          raise InfluxWriter::ClientError.new('unable to parse', 400) if calls == 1

          raise InfluxWriter::ServerError, 'gone'
        end
      end

      it 'stops splitting and keeps the batch queued' do
        expect { expect(described_class.run_once).to eq(0) }.not_to change(
          Outgoing,
          :count,
        )

        # The full batch, then the first half. The second half waits for the
        # next pass instead of running into another timeout.
        expect(InfluxWriter).to have_received(:write).twice
      end
    end

    # "Some or all of the data has been rejected. Data that has not been
    # rejected is ingested and queryable." -- so the good lines are already
    # stored and a split would only repeat what InfluxDB took.
    context 'when points are rejected on semantic grounds (422)' do
      before do
        allow(InfluxWriter).to receive(:write).and_raise(
          InfluxWriter::ClientError.new('partial write: field type conflict', 422),
        )
      end

      it 'clears the batch without splitting it' do
        expect { described_class.run_once }.to change(Outgoing, :count).by(-3)

        expect(InfluxWriter).to have_received(:write).once
      end

      it 'does not report the stored lines as dropped' do
        described_class.run_once

        expect($stderr.string).to include('it stored the rest')
        expect($stderr.string).not_to include('dropped')
      end
    end

    # A wrong token refuses the batch whatever its size. Splitting a batch of
    # 500 lines under one sent 999 requests.
    context 'when the token is refused (401)' do
      before do
        1.upto(20) { |i| target.outgoings.create!(line_protocol: "m f=#{i} 1000") }

        allow(InfluxWriter).to receive(:write).and_raise(
          InfluxWriter::ClientError.new('unauthorized', 401),
        )
      end

      it 'gives up after one request instead of splitting' do
        described_class.run_once

        expect(InfluxWriter).to have_received(:write).once
      end
    end

    # InfluxDB names the size it accepts and writes nothing, so a smaller
    # batch can still get through.
    context 'when the request is too large (413)' do
      before do
        allow(InfluxWriter).to receive(:write) do |lines, **|
          raise InfluxWriter::ClientError.new('request too large', 413) if lines.size > 1

          true
        end
      end

      it 'splits until the lines fit' do
        expect { expect(described_class.run_once).to eq(3) }.to change(
          Outgoing,
          :count,
        ).by(-3)
      end
    end

    context 'when a temporary write fails (ServerError)' do
      before do
        allow(InfluxWriter).to receive(:write).and_raise(
          InfluxWriter::ServerError.new('Influx down'),
        )
      end

      it 'keeps the outgoings for the next pass' do
        expect do
          processed = described_class.run_once
          expect(processed).to eq(0)
        end.not_to change(Outgoing, :count)
      end
    end

    # A queue of 100,000 rows must not run into 200 timeouts of 10 seconds
    # each. One failure per target and pass is enough.
    context 'when a target is unreachable' do
      before do
        # Enough rows for a second batch, so a pass that does not skip the
        # target would write twice.
        1.upto(described_class::BATCH_SIZE) do |i|
          target.outgoings.create!(line_protocol: "m field=#{i} 1000")
        end

        allow(InfluxWriter).to receive(:write).and_raise(
          InfluxWriter::ServerError.new('Influx down'),
        )
      end

      it 'tries the target once per pass' do
        described_class.run_once

        expect(InfluxWriter).to have_received(:write).once
      end
    end

    # A target that InfluxDB cannot reach must not hold back the queue of
    # another target.
    context 'when one of two targets is unreachable' do
      let(:other_target) do
        Target.create!(
          influx_token: 'other-token',
          bucket: 'other-bucket',
          org: 'other-org',
        )
      end

      before do
        other_target.outgoings.create!(line_protocol: 'measurement4 field=4 1000')

        allow(InfluxWriter).to receive(:write).and_return(true)
        allow(InfluxWriter).to receive(:write).with(
          anything,
          hash_including(influx_token: target.influx_token),
        ).and_raise(InfluxWriter::ServerError.new('Influx down'))
      end

      it 'writes the reachable target and keeps the other queued' do
        expect do
          processed = described_class.run_once
          expect(processed).to eq(1)
        end.to change(Outgoing, :count).by(-1)

        expect(Outgoing.pluck(:line_protocol)).to contain_exactly(
          'measurement1 field=1 1000',
          'measurement2 field=2 1000',
          'measurement3 field=3 2000',
        )
      end
    end
  end

  describe '.run_loop' do
    before { allow(described_class).to receive(:run_once).and_return(0) }

    it 'waits for signal and runs run_once' do
      thread = Thread.new { described_class.run_loop }

      # Simulate a signal to wake up the thread
      sleep 0.1
      OutboxNotifier.notify!

      sleep 0.1
      thread.kill
      thread.join

      expect(described_class).to have_received(:run_once).at_least(:once)
    end

    context 'when run_once raises' do
      before do
        allow(described_class).to receive(:sleep)

        calls = 0
        allow(described_class).to receive(:run_once) do
          calls += 1
          raise 'boom' if calls == 1

          0
        end
      end

      it 'reports the error and keeps the loop alive' do
        thread = Thread.new { described_class.run_loop }

        sleep 0.1
        alive = thread.alive?
        thread.kill
        thread.join

        expect(alive).to be true
        expect(described_class).to have_received(:run_once).at_least(:twice)
      end
    end
  end
end
