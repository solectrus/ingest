describe HousePowerCalculator do
  subject(:calculator) { described_class.new(target) }

  let(:target) do
    Target.create!(
      influx_token: 'test-token',
      bucket: 'test-bucket',
      org: 'test-org',
    )
  end

  let(:timestamp) { 1_000_000_000 }

  before do
    # Create Incoming for all relevant fields
    {
      %w[SENEC inverter_power] => 500,
      %w[SENEC bat_power_plus] => 200,
      %w[SENEC bat_power_minus] => 0,
      %w[SENEC grid_power_plus] => 0,
      %w[SENEC grid_power_minus] => 0,
      %w[SENEC wallbox_charge_power] => 0,
      %w[SENEC house_power] => 9999,
      %w[balcony inverter_power] => 0,
      %w[Heatpump power] => 0,
    }.each do |(measurement, field), value|
      Incoming.create!(
        target:,
        timestamp:,
        measurement:,
        field:,
        value:,
      )
    end
  end

  describe '#recalculate_many' do
    it 'calculates house power and stores outgoing line' do
      expect { calculator.recalculate_many(timestamps: [timestamp]) }.to change(Outgoing, :count).by(1)

      outgoing = Outgoing.last
      expect(outgoing.line_protocol).to eq(
        "SENEC house_power=300i #{timestamp}",
      )
    end

    it 'tracks recalculate' do
      expect(Stats.counter(:house_power_recalculates)).to eq(0)
      calculator.recalculate_many(timestamps: [timestamp])
      expect(Stats.counter(:house_power_recalculates)).to eq(1)
    end

    it 'tracks cache hit' do
      calculator.recalculate_many(timestamps: [timestamp])
      expect(Stats.counter(:house_power_recalculate_cache_hits)).to eq(1)
    end

    it 'tracks cache miss when requesting timestamp older than cache' do
      calculator.recalculate_many(timestamps: [timestamp - 1])
      expect(Stats.counter(:house_power_recalculate_cache_hits)).to eq(0)
    end

    it 'tracks cache miss when one field is not in cache' do
      SensorValueCache.instance.delete(measurement: 'SENEC', field: 'grid_power_minus')
      calculator.recalculate_many(timestamps: [timestamp])
      expect(Stats.counter(:house_power_recalculate_cache_hits)).to eq(0)
    end

    # A backfill carries one timestamp per collector poll. One query and one
    # insert per timestamp held the write lock for the whole request.
    context 'with several timestamps' do
      let(:timestamps) { [timestamp - 20, timestamp - 10, timestamp] }

      # An older sample per sensor, so the timestamps between the two sets can
      # be interpolated. The cache keeps the newer one, so it still answers
      # the newest timestamp only.
      before do
        Incoming.where(target:, timestamp:).find_each do |incoming|
          Incoming.create!(
            target:,
            timestamp: timestamp - 100,
            measurement: incoming.measurement,
            field: incoming.field,
            value: incoming.value,
          )
        end
      end

      it 'queues one line per timestamp' do
        expect { calculator.recalculate_many(timestamps:) }.to change(
          Outgoing,
          :count,
        ).by(3)
      end

      it 'writes the queue in one statement' do
        inserts = count_inserts { calculator.recalculate_many(timestamps:) }

        expect(inserts).to eq(1)
      end

      it 'counts one recalculation per timestamp' do
        calculator.recalculate_many(timestamps:)

        expect(Stats.counter(:house_power_recalculates)).to eq(3)
      end

      it 'ignores a repeated timestamp' do
        expect do
          calculator.recalculate_many(timestamps: [timestamp, timestamp])
        end.to change(Outgoing, :count).by(1)

        expect(Stats.counter(:house_power_recalculates)).to eq(1)
      end

      # The cache holds the newest value of a sensor only, so it answers the
      # newest timestamp and the older ones go to the interpolator.
      it 'takes the cache where it answers and interpolates the rest' do
        calculator.recalculate_many(timestamps:)

        expect(Stats.counter(:house_power_recalculate_cache_hits)).to eq(1)
      end

      it 'reports how many lines it queued' do
        expect(calculator.recalculate_many(timestamps:)).to eq(3)
      end
    end

    context 'without any timestamp' do
      it 'writes nothing' do
        expect { calculator.recalculate_many(timestamps: []) }.not_to change(
          Outgoing,
          :count,
        )
      end

      it 'reports that it queued nothing' do
        expect(calculator.recalculate_many(timestamps: [])).to eq(0)
      end
    end

    context 'with stale sensor data' do
      let(:stale_timestamp) { timestamp + described_class::MAX_SENSOR_AGE_NS + 1 }
      let(:fresh_timestamp) { timestamp + described_class::MAX_SENSOR_AGE_NS }

      it 'skips writing house_power when any sensor is stale' do
        expect { calculator.recalculate_many(timestamps: [stale_timestamp]) }.not_to change(Outgoing, :count)
      end

      it 'still recalculates at the max_age boundary' do
        expect { calculator.recalculate_many(timestamps: [fresh_timestamp]) }.to change(Outgoing, :count).by(1)
      end

      it 'tracks the skip' do
        calculator.recalculate_many(timestamps: [stale_timestamp])
        expect(Stats.counter(:house_power_recalculate_skipped)).to eq(1)
      end

      it 'tracks the stale sensor by key' do
        calculator.recalculate_many(timestamps: [stale_timestamp])
        expect(Stats.counter(:house_power_skip_inverter_power)).to eq(1)
      end
    end

    context 'when the formula has no result' do
      before { allow(HousePowerFormula).to receive(:calculate).and_return(nil) }

      it 'writes nothing' do
        expect { calculator.recalculate_many(timestamps: [timestamp]) }.not_to change(
          Outgoing,
          :count,
        )
      end

      it 'leaves house_power_last_success_at unset' do
        calculator.recalculate_many(timestamps: [timestamp])

        expect(Stats.value(:house_power_last_success_at)).to be_nil
      end

      it 'reports that it queued nothing' do
        expect(calculator.recalculate_many(timestamps: [timestamp])).to eq(0)
      end
    end

    context 'when a sensor is configured without a field' do
      before do
        allow(SensorEnvConfig).to receive(:[]).and_call_original
        allow(SensorEnvConfig).to receive(:[]).with(:inverter_power).and_return(
          { measurement: 'SENEC', field: nil },
        )
      end

      # The cache lookup gives up, so the calculator falls back to the
      # interpolator, which drops the incomplete sensor
      it 'does not count a cache hit' do
        calculator.recalculate_many(timestamps: [timestamp])

        expect(Stats.counter(:house_power_recalculate_cache_hits)).to eq(0)
      end
    end

    describe 'last success timestamp' do
      it 'sets house_power_last_success_at after a successful write' do
        before_call = Time.now.to_i
        calculator.recalculate_many(timestamps: [timestamp])
        expect(Stats.value(:house_power_last_success_at)).to be_within(2).of(before_call)
      end

      it 'leaves house_power_last_success_at unset when skipped' do
        stale = timestamp + described_class::MAX_SENSOR_AGE_NS + 1
        calculator.recalculate_many(timestamps: [stale])
        expect(Stats.value(:house_power_last_success_at)).to be_nil
      end
    end
  end

  def count_inserts
    count = 0
    subscriber =
      ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
        count += 1 if payload[:sql].start_with?('INSERT')
      end
    yield
    count
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end
end
