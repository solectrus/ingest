describe Interpolator do
  let(:timestamp) { 1_000 }
  let(:max_age) { 1_000 }

  let(:target) do
    Target.create!(
      influx_token: 'foo',
      bucket: 'test',
      org: 'test',
    )
  end

  before do
    target.incomings.create!(
      measurement: 'SENEC',
      field: 'inverter_power',
      timestamp: 990,
      value: 1000,
    )
    target.incomings.create!(
      measurement: 'SENEC',
      field: 'inverter_power',
      timestamp: 1010,
      value: 1200,
    )

    target.incomings.create!(
      measurement: 'SENEC',
      field: 'wallbox_charge_power',
      timestamp: 980,
      value: 0,
    )
  end

  it 'returns interpolated values from real ENV sensor config' do
    result =
      described_class.new(
        sensor_keys: %i[inverter_power wallbox_power],
        timestamps: [timestamp],
        max_age:,
      ).run[timestamp] || {}

    expect(result[:inverter_power]).to eq(1100.0)
    expect(result[:wallbox_power]).to eq(0.0)
  end

  it 'returns nothing if all sensors are missing' do
    result =
      described_class.new(
        sensor_keys: %i[inverter_power_1 grid_import_power],
        timestamps: [timestamp],
        max_age:,
      ).run[timestamp] || {}
    expect(result).to be_empty
  end

  it 'ignores sensors not set in ENV' do
    stub_const(
      'ENV',
      ENV.to_hash.merge('INFLUX_SENSOR_GRID_IMPORT_POWER' => ''),
    )

    result =
      described_class.new(
        sensor_keys: %i[inverter_power grid_import_power],
        timestamps: [timestamp],
        max_age:,
      ).run[timestamp] || {}
    expect(result.keys).to eq([:inverter_power])
  end

  it 'omits sensors whose only prev sample is older than max_age' do
    # wallbox_charge_power has a single prev sample at timestamp 980,
    # 20 units older than the target timestamp.
    result =
      described_class.new(
        sensor_keys: %i[inverter_power wallbox_power],
        timestamps: [timestamp],
        max_age: 10,
      ).run[timestamp] || {}

    expect(result.keys).to eq([:inverter_power])
  end

  it 'still interpolates between two samples regardless of max_age' do
    # inverter_power has prev (990) and next (1010) — interpolation is
    # always valid for surrounding samples.
    result =
      described_class.new(
        sensor_keys: %i[inverter_power],
        timestamps: [timestamp],
        max_age: 1,
      ).run[timestamp] || {}

    expect(result[:inverter_power]).to eq(1100.0)
  end

  # Two sensor keys can name the same measurement and field. The query asks
  # for each pair once, and both keys read the same answer.
  it 'resolves two sensor keys that share one measurement and field' do
    stub_const(
      'ENV',
      ENV.to_hash.merge(
        'INFLUX_SENSOR_INVERTER_POWER_1' => 'SENEC:inverter_power',
      ),
    )
    SensorEnvConfig.reset!

    result =
      described_class.new(
        sensor_keys: %i[inverter_power inverter_power_1],
        timestamps: [timestamp],
        max_age:,
      ).run[timestamp] || {}

    expect(result[:inverter_power]).to eq(1100.0)
    expect(result[:inverter_power_1]).to eq(1100.0)
  end

  # A collector that runs into a timeout sends its batch again, so two rows can
  # carry the same measurement, field and timestamp. Without a rule the answer
  # would depend on the order the database returns the rows.
  describe 'repeated timestamps' do
    def add(timestamp, value, field: 'inverter_power')
      target.incomings.create!(
        measurement: 'SENEC',
        field:,
        timestamp:,
        value:,
      )
    end

    it 'takes the row written last when a sample is repeated' do
      add(1_000, 500)
      add(1_000, 700) # the retry

      result =
        described_class.new(
          sensor_keys: %i[inverter_power],
          timestamps: [1_000],
          max_age:,
        ).run

      expect(result[1_000][:inverter_power]).to eq(700)
    end

    it 'takes the row written last for a bound before the window' do
      add(900, 500)
      add(900, 700)

      result =
        described_class.new(
          sensor_keys: %i[inverter_power],
          timestamps: [950],
          max_age: 100,
        ).run

      # 950 sits between the repeated sample at 900 and the one at 990. The
      # retry wrote 700, so that is the lower bound — 500 would give 777.8.
      expect(result[950][:inverter_power]).to eq(
        700 + ((1000 - 700) * (950 - 900).to_f / (990 - 900)),
      )
    end

    it 'takes the row written last for a bound after the window' do
      add(1_010, 999) # repeats the sample the outer before block adds

      result =
        described_class.new(
          sensor_keys: %i[inverter_power],
          timestamps: [1_000],
          max_age:,
        ).run

      expect(result[1_000][:inverter_power]).to eq(999.5)
    end

    # The rows of the three branches arrive in one result set, and nothing
    # promises an order inside it. The rule has to hold whatever that order is.
    it 'does not depend on the order the database returns the rows' do
      add(1_000, 500)
      add(1_000, 700) # the retry

      connection = ActiveRecord::Base.connection
      original = connection.method(:exec_query)
      allow(connection).to receive(:exec_query) do |*args|
        result = original.call(*args)
        ActiveRecord::Result.new(result.columns, result.rows.reverse)
      end

      result =
        described_class.new(
          sensor_keys: %i[inverter_power],
          timestamps: [1_000],
          max_age:,
        ).run

      expect(result[1_000][:inverter_power]).to eq(700)
    end

    it 'answers the same however often it runs' do
      add(1_000, 500)
      add(1_000, 700)
      add(1_000, 600)

      answers =
        Array.new(5) do
          described_class.new(
            sensor_keys: %i[inverter_power],
            timestamps: [1_000],
            max_age:,
          ).run
        end

      expect(answers.uniq.size).to eq(1)
    end
  end

  describe 'several timestamps' do
    it 'answers each timestamp of one call' do
      result =
        described_class.new(
          sensor_keys: %i[inverter_power],
          timestamps: [995, 1_000, 1_005],
          max_age:,
        ).run

      expect(result[995][:inverter_power]).to eq(1050.0)
      expect(result[1_000][:inverter_power]).to eq(1100.0)
      expect(result[1_005][:inverter_power]).to eq(1150.0)
    end

    it 'returns the sample itself when a timestamp matches it exactly' do
      result =
        described_class.new(
          sensor_keys: %i[inverter_power],
          timestamps: [990, 1_010],
          max_age:,
        ).run

      expect(result[990][:inverter_power]).to eq(1000)
      expect(result[1_010][:inverter_power]).to eq(1200)
    end

    it 'accepts the timestamps in any order' do
      result =
        described_class.new(
          sensor_keys: %i[inverter_power],
          timestamps: [1_005, 995, 1_005],
          max_age:,
        ).run

      expect(result.keys).to eq([995, 1_005])
    end

    # One query per timestamp made a backfill of 5000 points cost 5000
    # queries. The timestamps of one window now share a single query.
    it 'asks the database once per window, not once per timestamp' do
      timestamps = (1..600).map { |i| 900 + i }

      queries = count_queries do
        described_class.new(
          sensor_keys: %i[inverter_power],
          timestamps:,
          max_age:,
        ).run
      end

      expect(timestamps.size).to eq(600)
      expect(queries).to eq(1)
    end

    # The window decides how many queries a run makes. It must not decide what
    # the run answers, so the same data has to give the same result whatever
    # the window covers.
    context 'with gaps between the samples' do
      before do
        [1_100, 1_130, 1_400, 1_405, 1_410, 2_000].each do |ts|
          target.incomings.create!(
            measurement: 'SENEC',
            field: 'inverter_power',
            timestamp: ts,
            value: ts * 2,
          )
          next if ts == 1_400

          target.incomings.create!(
            measurement: 'SENEC',
            field: 'wallbox_charge_power',
            timestamp: ts + 3,
            value: ts,
          )
        end
      end

      it 'answers the same whatever the window covers' do
        timestamps = (0..60).map { |i| 980 + (i * 17) }

        # The four spans hold 1, 2, 24 and all 61 of these timestamps. The run
        # then makes 61, 31, 3 and 1 queries, and every one of them must give
        # the same answer.
        results =
          [1, 25, 400, 1_000_000].map do |span|
            stub_const("#{described_class}::MAX_WINDOW_SPAN_NS", span)

            described_class.new(
              sensor_keys: %i[inverter_power wallbox_power],
              timestamps:,
              max_age: 200,
            ).run
          end

        expect(results.first).not_to be_empty
        expect(results.uniq.size).to eq(1)
      end
    end

    # A collector that drops equal values sends few timestamps for a long
    # period. Such a window would load the samples of many hours at once.
    it 'starts a new window when the span grows too large' do
      step = described_class::MAX_WINDOW_SPAN_NS + 1

      queries = count_queries do
        described_class.new(
          sensor_keys: %i[inverter_power],
          timestamps: [1_000, 1_000 + step, 1_000 + (2 * step)],
          max_age:,
        ).run
      end

      expect(queries).to eq(3)
    end

    it 'keeps a window that spans exactly the limit' do
      queries = count_queries do
        described_class.new(
          sensor_keys: %i[inverter_power],
          timestamps: [1_000, 1_000 + described_class::MAX_WINDOW_SPAN_NS],
          max_age:,
        ).run
      end

      expect(queries).to eq(1)
    end
  end

  def count_queries
    count = 0
    subscriber =
      ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
        count += 1 unless payload[:name] == 'SCHEMA'
      end
    yield
    count
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  describe '#run' do
    context 'without configured sensors' do
      it 'returns an empty hash' do
        interpolator =
          described_class.new(sensor_keys: [], timestamps: [1_000], max_age: 1_000)

        expect(interpolator.run).to eq({})
      end
    end
  end
end
