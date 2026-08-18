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

  describe '#recalculate' do
    it 'calculates house power and stores outgoing line' do
      expect { calculator.recalculate(timestamp:) }.to change(Outgoing, :count).by(1)

      outgoing = Outgoing.last
      expect(outgoing.line_protocol).to eq(
        "SENEC house_power=300i #{timestamp}",
      )
    end

    it 'tracks recalculate' do
      expect(Stats.counter(:house_power_recalculates)).to eq(0)
      calculator.recalculate(timestamp:)
      expect(Stats.counter(:house_power_recalculates)).to eq(1)
    end

    it 'tracks cache hit' do
      calculator.recalculate(timestamp:)
      expect(Stats.counter(:house_power_recalculate_cache_hits)).to eq(1)
    end

    it 'tracks cache miss when requesting timestamp older than cache' do
      calculator.recalculate(timestamp: timestamp - 1)
      expect(Stats.counter(:house_power_recalculate_cache_hits)).to eq(0)
    end

    it 'tracks cache miss when one field is not in cache' do
      SensorValueCache.instance.delete(measurement: 'SENEC', field: 'grid_power_minus')
      calculator.recalculate(timestamp: timestamp)
      expect(Stats.counter(:house_power_recalculate_cache_hits)).to eq(0)
    end

    context 'with stale sensor data' do
      let(:stale_timestamp) { timestamp + described_class::MAX_SENSOR_AGE_NS + 1 }
      let(:fresh_timestamp) { timestamp + described_class::MAX_SENSOR_AGE_NS }

      it 'skips writing house_power when any sensor is stale' do
        expect { calculator.recalculate(timestamp: stale_timestamp) }.not_to change(Outgoing, :count)
      end

      it 'still recalculates at the max_age boundary' do
        expect { calculator.recalculate(timestamp: fresh_timestamp) }.to change(Outgoing, :count).by(1)
      end

      it 'tracks the skip' do
        calculator.recalculate(timestamp: stale_timestamp)
        expect(Stats.counter(:house_power_recalculate_skipped)).to eq(1)
      end

      it 'tracks the stale sensor by key' do
        calculator.recalculate(timestamp: stale_timestamp)
        expect(Stats.counter(:house_power_skip_inverter_power)).to eq(1)
      end
    end

    context 'when the formula has no result' do
      before { allow(HousePowerFormula).to receive(:calculate).and_return(nil) }

      it 'writes nothing' do
        expect { calculator.recalculate(timestamp:) }.not_to change(
          Outgoing,
          :count,
        )
      end

      it 'leaves house_power_last_success_at unset' do
        calculator.recalculate(timestamp:)

        expect(Stats.value(:house_power_last_success_at)).to be_nil
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
        calculator.recalculate(timestamp:)

        expect(Stats.counter(:house_power_recalculate_cache_hits)).to eq(0)
      end
    end

    describe 'last success timestamp' do
      it 'sets house_power_last_success_at after a successful write' do
        before_call = Time.now.to_i
        calculator.recalculate(timestamp:)
        expect(Stats.value(:house_power_last_success_at)).to be_within(2).of(before_call)
      end

      it 'leaves house_power_last_success_at unset when skipped' do
        stale = timestamp + described_class::MAX_SENSOR_AGE_NS + 1
        calculator.recalculate(timestamp: stale)
        expect(Stats.value(:house_power_last_success_at)).to be_nil
      end
    end
  end
end
