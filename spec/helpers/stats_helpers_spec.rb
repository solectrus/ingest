describe StatsHelpers do
  include described_class
  include ActiveSupport::NumberHelper

  describe 'incoming counts' do
    let(:target) do
      Target.create!(influx_token: 'foo', bucket: 'test', org: 'test')
    end

    before do
      2.times do
        target.incomings.create!(measurement: 'SENEC', field: 'a', value: 1)
      end
      target.incomings.create!(measurement: 'SENEC', field: 'b', value: 1)
    end

    describe '#incoming_total' do
      it 'sums the grouped counts' do
        expect(incoming_total).to eq(3)
      end
    end

    describe '#other_measurement_fields_grouped' do
      it 'groups the fields by measurement' do
        expect(other_measurement_fields_grouped.keys).to eq(%w[SENEC])
        expect(other_measurement_fields_grouped['SENEC'].map { it[:field] })
          .to eq(%w[a b])
      end

      # SQLite does not promise the order of a grouped scan, so the list sorts
      # the fields itself. A reader looks a field up by its name.
      it 'sorts the fields of a measurement by name' do
        allow(self).to receive(:incoming_by_target).and_return(
          {
            %w[SENEC b] => { count: 1, last_at: Time.current },
            %w[SENEC a] => { count: 1, last_at: Time.current },
          },
        )

        expect(other_measurement_fields_grouped['SENEC'].map { it[:field] })
          .to eq(%w[a b])
      end

      # The list of sensors above already names it, with the same throughput.
      it 'leaves out a field that a configured sensor reads' do
        measurement, field =
          SensorEnvConfig[:inverter_power].values_at(:measurement, :field)
        target.incomings.create!(measurement:, field:, value: 1)

        fields =
          other_measurement_fields_grouped
            .values
            .flatten
            .map { |entry| entry[:field] }

        expect(fields).not_to include(field)
      end

      # The total, the sensor list and the cards all read the same grouped
      # scan. Each one of its own would scan the index again.
      it 'shares its scan with #incoming_total and #configured_sensors' do
        scans = 0
        subscriber =
          ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
            sql = payload[:sql]
            scans += 1 if sql.include?('FROM "incomings"') && sql.include?('GROUP BY')
          end

        incoming_total
        configured_sensors
        other_measurement_fields_grouped

        expect(scans).to eq(1)
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber)
      end

      # MAX(created_at) makes the scan read the table row of every line,
      # because `created_at` is not in the index. MAX(id) reads the rowid,
      # which every index holds: 369ms against 73ms on 800,000 lines.
      it 'reads the index alone' do
        sql = Incoming.group(:measurement, :field).select(Arel.sql(described_class::INCOMING_COLUMNS)).to_sql
        plan = ActiveRecord::Base.connection.select_all("EXPLAIN QUERY PLAN #{sql}")

        expect(plan.map { it['detail'] }).to all(include('COVERING INDEX'))
      end

      # A line that arrived once and stopped keeps its throughput for the
      # whole retention period. Only the age says that nothing arrives now.
      it 'reports the age of the last line of a field' do
        target.incomings.create!(
          measurement: 'Shelly', field: 'power', value: 1,
          created_at: 10.minutes.ago,
        )

        entry = other_measurement_fields_grouped['Shelly'].first

        expect(entry[:age]).to be_within(5).of(10.minutes)
      end
    end
  end

  describe '#value_or_dash' do
    it 'returns a dash for nil' do
      expect(value_or_dash(nil)).to eq('–')
    end

    it 'returns the value if no block is given' do
      expect(value_or_dash(42)).to eq(42)
    end

    it 'gives the value to the block' do
      expect(value_or_dash(42) { |value| "#{value} W" }).to eq('42 W')
    end
  end

  describe '#format_age' do
    it 'names how long ago the server measured the value' do
      expect(format_age(65.4)).to eq('1m 5s ago')
    end

    # The script counted these values up before, and they then disagreed with
    # the throughput and the counts, which keep the moment of the request.
    # Only the header of the page carries a value that grows.
    it 'carries nothing for the script to count up' do
      expect(format_age(65.4)).not_to include('data-age')
    end
  end

  describe '#format_duration' do
    it 'returns a dash for nil' do
      expect(format_duration(nil)).to eq('–')
    end

    it 'formats seconds only' do
      expect(format_duration(12)).to eq('12s')
    end

    it 'formats minutes and seconds' do
      expect(format_duration(75)).to eq('1m 15s')
    end

    it 'formats hours and minutes' do
      expect(format_duration(3600 + (2 * 60))).to eq('1h 2m')
    end

    it 'formats days, hours and minutes' do
      expect(format_duration((2 * 86_400) + 3600 + 120)).to eq('2d 1h 2m')
    end

    it 'rounds down incomplete minutes and seconds' do
      expect(format_duration(3661)).to eq('1h 1m') # 1 hour, 1 min, 1 sec → no secs shown
    end
  end

  describe 'house power calculation stats' do
    describe '#calculation_rate' do
      it 'returns nil without calculations' do
        expect(calculation_rate).to be_nil
      end

      it 'returns the calculations per minute' do
        3.times { Stats.inc(:house_power_recalculates) }
        allow(self).to receive(:container_uptime).and_return(60.0)

        expect(calculation_rate).to eq(3.0)
      end
    end

    describe '#interpolate_queries_per_request' do
      it 'returns nil without requests' do
        expect(interpolate_queries_per_request).to be_nil
      end

      # The misses of one request share a single query, so the ratio stays
      # near or below 1 even when the hit rate is low.
      it 'returns the queries per request' do
        4.times { Stats.inc(:http_requests) }
        3.times { Stats.inc(:interpolate_queries) }

        expect(interpolate_queries_per_request).to eq(0.75)
      end
    end

    describe '#calculation_cache_hits' do
      it 'returns nil without calculations' do
        expect(calculation_cache_hits).to be_nil
      end

      it 'returns the percentage of cache hits' do
        4.times { Stats.inc(:house_power_recalculates) }
        Stats.inc(:house_power_recalculate_cache_hits)

        expect(calculation_cache_hits).to eq(25.0)
      end
    end

    describe '#interpolate_queries' do
      it 'returns zero without queries' do
        expect(interpolate_queries).to eq(0)
      end

      it 'returns the number of interpolator queries' do
        3.times { Stats.inc(:interpolate_queries) }

        expect(interpolate_queries).to eq(3)
      end
    end

    describe '#calculation_skipped' do
      it 'returns nil without calculations' do
        expect(calculation_skipped).to be_nil
      end

      it 'returns the percentage of skipped calculations' do
        4.times { Stats.inc(:house_power_recalculates) }
        3.times { Stats.inc(:house_power_recalculate_skipped) }

        expect(calculation_skipped).to eq(75.0)
      end
    end

    describe '#calculation_skips_by_sensor' do
      let(:prefix) { HousePowerCalculator::SKIP_STAT_PREFIX }

      it 'returns an empty list without skips' do
        expect(calculation_skips_by_sensor).to eq([])
      end

      it 'strips the prefix and sorts by count, descending' do
        Stats.inc(:"#{prefix}grid_import_power")
        2.times { Stats.inc(:"#{prefix}inverter_power") }

        expect(calculation_skips_by_sensor).to eq(
          [%w[inverter_power].push(2), %w[grid_import_power].push(1)],
        )
      end
    end

    describe '#last_calculation_age' do
      it 'returns nil without a calculation' do
        expect(last_calculation_age).to be_nil
      end

      it 'returns the age of the last calculation' do
        Stats.set(:house_power_last_success_at, 30.seconds.ago.to_i)

        expect(last_calculation_age).to be_within(5).of(30)
      end
    end
  end

  describe '#response_time' do
    it 'returns nil without requests' do
      expect(response_time).to be_nil
    end

    it 'returns the rounded average duration' do
      2.times { Stats.inc(:http_requests) }
      Stats.add(:http_duration_total, 7.0)

      expect(response_time).to eq(4)
    end
  end

  describe 'throughput' do
    let(:target) do
      Target.create!(influx_token: 'foo', bucket: 'test', org: 'test')
    end

    describe '#incoming_lines_rate' do
      it 'returns nothing before the first line' do
        expect(incoming_lines).to eq(0)
        expect(incoming_lines_rate).to be_nil
      end

      # The buffer holds a row per field, so it cannot answer how many lines
      # arrived. The counter can, and only it compares with the delivery rate.
      it 'returns the lines per minute since the start' do
        Stats.inc(:incoming_lines, 20)
        allow(self).to receive(:container_uptime).and_return(120)

        expect(incoming_lines_rate).to eq(10.0)
      end
    end

    describe '#incoming_values_rate' do
      it 'returns nothing before the first value' do
        expect(incoming_values).to eq(0)
        expect(incoming_values_rate).to be_nil
      end

      it 'returns the values per minute since the start' do
        Stats.inc(:incoming_values, 60)
        allow(self).to receive(:container_uptime).and_return(120)

        expect(incoming_values_rate).to eq(30.0)
      end
    end

    describe '#outgoing_delivered_values_rate' do
      it 'returns nothing before the first value' do
        expect(outgoing_delivered_values).to eq(0)
        expect(outgoing_delivered_values_rate).to be_nil
      end

      it 'returns the values per minute since the start' do
        Stats.inc(:outgoing_delivered_values, 90)
        allow(self).to receive(:container_uptime).and_return(120)

        expect(outgoing_delivered_values_rate).to eq(45.0)
      end
    end

    describe '#incoming_throughput_for' do
      it 'returns nil without a range' do
        expect(incoming_throughput_for(10)).to be_nil
      end

      it 'returns the lines per minute for the given count' do
        target.incomings.create!(
          measurement: 'SENEC',
          field: 'test',
          value: 42,
          created_at: 2.minutes.ago,
        )
        target.incomings.create!(
          measurement: 'SENEC',
          field: 'test',
          value: 42,
          created_at: Time.current,
        )

        expect(incoming_throughput_for(10)).to eq(5.0)
      end
    end
  end

  describe '#throughput_tag' do
    it 'returns a dash for nil' do
      expect(throughput_tag(nil)).to eq('<small>-</small>')
    end

    # Every 4 seconds is the fastest rate that SOLECTRUS uses.
    it 'marks a rate up to every 4 seconds as ok' do
      expect(throughput_tag(15)).to eq('<small class="ok">15 /min</small>')
    end

    it 'marks a faster rate as warn' do
      expect(throughput_tag(15.2)).to eq('<small class="warn">15 /min</small>')
      expect(throughput_tag(30)).to eq('<small class="warn">30 /min</small>')
    end

    it 'marks a rate above every 2 seconds as crit' do
      expect(throughput_tag(31)).to eq('<small class="crit">31 /min</small>')
    end

    it 'keeps the decimal of a slow rate' do
      expect(throughput_tag(0.4)).to eq('<small class="ok">0.4 /min</small>')
    end
  end

  describe '#format_rate' do
    it 'returns nothing without a value' do
      expect(format_rate(nil)).to be_nil
    end

    # A rate that rounds to 0 reads as "nothing arrives".
    it 'keeps one decimal below 10' do
      expect(format_rate(0.44)).to eq('0.4 /min')
      expect(format_rate(9.94)).to eq('9.9 /min')
    end

    it 'drops the decimal from 10 upwards' do
      expect(format_rate(9.96)).to eq('10 /min')
      expect(format_rate(24.2)).to eq('24 /min')
      expect(format_rate(1234.5)).to eq('1,235 /min')
    end
  end

  describe '#incoming_age' do
    let(:target) do
      Target.create!(influx_token: 'foo', bucket: 'test', org: 'test')
    end

    it 'returns nil without a line' do
      expect(incoming_age).to be_nil
      expect(status_of(:incoming_age)).to be_nil
    end

    it 'returns how long ago the last line arrived' do
      target.incomings.create!(
        measurement: 'SENEC', field: 'a', value: 1, created_at: 2.minutes.ago,
      )

      expect(incoming_age).to be_within(5).of(120)
      expect(status_of(:incoming_age)).to be_nil
    end

    # An ingest that nobody feeds keeps its total, its range and its
    # throughput, so only the age tells that the collectors stopped.
    it 'reports a long silence as critical' do
      target.incomings.create!(
        measurement: 'SENEC', field: 'a', value: 1, created_at: 20.minutes.ago,
      )

      expect(status_of(:incoming_age)).to eq('crit')
    end
  end

  describe '#incoming_newest' do
    let(:target) do
      Target.create!(influx_token: 'foo', bucket: 'test', org: 'test')
    end

    before do
      target.incomings.create!(
        measurement: 'SENEC', field: 'a', value: 1, created_at: 3.minutes.ago,
      )
      target.incomings.create!(
        measurement: 'SENEC', field: 'b', value: 1, created_at: 2.minutes.ago,
      )
      target.incomings.create!(
        measurement: 'OTHER', field: 'a', value: 1, created_at: 1.minute.ago,
      )
    end

    it 'matches the maximum of the table' do
      expect(incoming_newest).to eq(Incoming.maximum(:created_at))
    end

    # The scan of the measurements and fields already holds the answer.
    it 'asks no query of its own' do
      incoming_counts

      queries = count_queries { incoming_newest }

      expect(queries).to be_zero
    end

    # The cleanup can delete a row between the two queries of the scan.
    it 'ignores an entry whose row went away' do
      allow(self).to receive(:incoming_by_target).and_return(
        { %w[SENEC a] => { count: 1, last_at: nil } },
      )

      expect(incoming_newest).to be_nil
    end
  end

  describe '#incoming_oldest' do
    it 'asks no query for an empty buffer' do
      queries = count_queries { 2.times { incoming_oldest } }

      expect(queries).to eq(1) # The scan of the measurements and fields
    end
  end

  describe '#stale_sensors' do
    let(:target) do
      Target.create!(influx_token: 'foo', bucket: 'test', org: 'test')
    end

    # Every configured sensor gets a line. The named one gets its last line
    # earlier, so it alone falls behind.
    def deliver_all(stopped: nil, ago: 0.seconds)
      SensorEnvConfig.config.each do |key, sensor|
        target.incomings.create!(
          measurement: sensor[:measurement],
          field: sensor[:field],
          value: 1,
          created_at: (key == stopped ? ago.ago : Time.current),
        )
      end
    end

    it 'stays empty while every sensor delivers' do
      deliver_all

      expect(stale_sensors).to be_empty
      expect(status_of(:sensors_stale)).to be_nil
      expect(sensors_summary).to be_nil
    end

    it 'stays empty while a sensor is late but within the limit' do
      deliver_all(stopped: :inverter_power, ago: 14.minutes)

      expect(stale_sensors).to be_empty
      expect(status_of(:sensors_stale)).to be_nil
    end

    it 'names a sensor that stopped' do
      deliver_all(stopped: :inverter_power, ago: 20.minutes)

      expect(stale_sensors.map { it[:key] }).to eq([:inverter_power])
      expect(status_of(:sensors_stale)).to eq('crit')
      expect(page_status).to eq('crit')
      expect(sensors_summary).to eq("1 of #{included_sensors.size} stale")
    end

    # A typo in an INFLUX_SENSOR_* variable and a collector that stopped need
    # different repairs, so the summary must not merge them into one number.
    it 'names a sensor without data apart from a stale one' do
      measurement, field =
        SensorEnvConfig[:inverter_power].values_at(:measurement, :field)
      target.incomings.create!(
        measurement:, field:, value: 1, created_at: 20.minutes.ago,
      )

      total = included_sensors.size

      expect(sensors_summary).to eq(
        "#{total - 1} of #{total} without data, 1 of #{total} stale",
      )
      # A sensor that stopped is the worse of the two faults.
      expect(sensors_summary_level).to eq('crit')
    end
  end

  describe '#stream_tag' do
    it 'shows the rate while the stream runs' do
      entry = { throughput: 5, age: 12, stale: false, level: nil }

      expect(stream_tag(entry)).to eq('<small class="ok">5 /min</small>')
    end

    # The rate of a quiet stream is an average over the whole buffer. It keeps
    # the value it had while the stream ran, so it reads as healthy.
    it 'shows the age instead once the stream goes quiet' do
      entry = { throughput: 5, age: 1200, stale: true, level: 'crit' }

      expect(stream_tag(entry)).to eq('<small class="crit">20m 0s ago</small>')
    end

    # A forwarded stream can be slow on purpose, so its age is a fact and not
    # a fault.
    it 'leaves the age plain without a level' do
      entry = { throughput: 5, age: 600, stale: true, level: nil }

      expect(stream_tag(entry)).to eq('<small>10m 0s ago</small>')
    end
  end

  describe '#stale_level' do
    it 'accepts a stream that sent within the limit' do
      expect(stale_level(14.minutes)).to be_nil
    end

    it 'reports a stream that stopped as critical' do
      expect(stale_level(16.minutes)).to eq('crit')
    end
  end

  describe '#sensors_without_data' do
    let(:target) do
      Target.create!(influx_token: 'foo', bucket: 'test', org: 'test')
    end

    def configured(key)
      SensorEnvConfig[key].values_at(:measurement, :field)
    end

    it 'reports nothing while the buffer is empty' do
      expect(sensors_without_data).to be_empty
      expect(status_of(:sensors_without_data)).to be_nil
    end

    # A typo in an INFLUX_SENSOR_* variable and a collector that does not send
    # look the same otherwise: the sensor is absent from the measurements.
    it 'names a configured sensor that never arrives' do
      measurement, field = configured(:inverter_power)
      target.incomings.create!(measurement:, field:, value: 1)

      expect(sensors_without_data).to include(
        [:inverter_power_1, configured(:inverter_power_1).join(':')],
      )
      expect(sensors_without_data).not_to include(
        [:inverter_power, "#{measurement}:#{field}"],
      )
      expect(status_of(:sensors_without_data)).to eq('warn')
    end

    it 'stays quiet once every sensor has arrived' do
      SensorEnvConfig.config.each_value do |sensor|
        target.incomings.create!(
          measurement: sensor[:measurement], field: sensor[:field], value: 1,
        )
      end

      expect(sensors_without_data).to be_empty
      expect(status_of(:sensors_without_data)).to be_nil
    end

    # INFLUX_EXCLUDE_FROM_HOUSE_POWER says that Ingest must not use the
    # sensor. A value that nobody wants cannot be missing.
    it 'keeps a sensor that the house power excludes out of the list' do
      excluded = SensorEnvConfig.exclude_from_house_power_keys.first
      measurement, field = configured(:inverter_power)
      target.incomings.create!(measurement:, field:, value: 1)

      expect(sensors_without_data.map(&:first)).not_to include(excluded)
      expect(sensors_without_data.map(&:first)).to include(:inverter_power_1)
    end
  end

  describe '#included_sensors and #excluded_sensors' do
    let(:excluded) { SensorEnvConfig.exclude_from_house_power_keys.first }

    it 'splits the configuration along INFLUX_EXCLUDE_FROM_HOUSE_POWER' do
      expect(excluded_sensors.map { it[:key] }).to eq([excluded])
      expect(included_sensors.map { it[:key] }).not_to include(excluded)
      expect(included_sensors.size + excluded_sensors.size).to eq(
        configured_sensors.size,
      )
    end

    # The house power is the result of the formula, never an input, so the
    # variable cannot exclude it.
    it 'keeps the house power itself among the included sensors' do
      allow(SensorEnvConfig).to receive(:exclude_from_house_power_keys)
        .and_return(Set[:house_power])

      expect(excluded_sensors).to be_empty
      expect(included_sensors.map { it[:key] }).to include(:house_power)
    end
  end

  describe 'what happens to the incoming house power' do
    def sensor(key)
      configured_sensors.find { |entry| entry[:key] == key }
    end

    # Ingest calculates the house power from the other sensors. The list holds
    # the incoming one beside them, so the row has to say what Ingest does
    # with it. No other sensor carries such a note.
    it 'notes the house power and nothing else' do
      expect(sensor(:house_power)).to include(note: 'replaced')

      others = configured_sensors.reject { it[:key] == :house_power }
      expect(others).to all(include(note: nil))
    end

    # Without INFLUX_SENSOR_HOUSE_POWER_CALCULATED the result goes to the same
    # field, so the incoming value never reaches InfluxDB.
    it 'says "replaced" while the result goes to the same field' do
      expect(house_power_destination).to eq(sensor_source(:house_power))
      expect(house_power_note).to eq('replaced')
    end

    # With it the result goes to a field of its own, and the incoming value is
    # forwarded beside it.
    it 'says "kept" while the result goes to a field of its own' do
      allow(SensorEnvConfig).to receive(:house_power_destination)
        .and_return({ measurement: 'Calculated', field: 'house_power' })

      expect(house_power_note).to eq('kept')
    end
  end

  describe '#configured_sensors' do
    let(:target) do
      Target.create!(influx_token: 'foo', bucket: 'test', org: 'test')
    end

    def sensor(key)
      configured_sensors.find { |entry| entry[:key] == key }
    end

    # An empty buffer would mark every sensor, which says nothing. The age of
    # the newest line covers that case.
    it 'marks nothing while the buffer is empty' do
      expect(configured_sensors).to all(include(missing: false))
      expect(configured_sensors).to all(include(throughput: nil))
    end

    it 'names the measurement and the field of every configured sensor' do
      expect(sensor(:inverter_power)).to include(
        target: SensorEnvConfig[:inverter_power].values_at(:measurement, :field).join(':'),
      )
    end

    it 'marks a sensor that no line arrives for' do
      measurement, field =
        SensorEnvConfig[:inverter_power].values_at(:measurement, :field)
      target.incomings.create!(
        measurement:, field:, value: 1, created_at: 1.minute.ago,
      )
      target.incomings.create!(measurement:, field:, value: 2)

      expect(sensor(:inverter_power)).to include(missing: false)
      expect(sensor(:inverter_power)[:throughput]).to be_positive
      expect(sensor(:house_power)).to include(missing: true, throughput: nil)
    end

    # The buffer keeps the lines of a dead collector for the whole retention
    # period. The count, the time span and the throughput of the sensor all
    # keep the value they had while it ran, so only the age can report it.
    it 'reports a sensor that arrived and then stopped' do
      measurement, field =
        SensorEnvConfig[:inverter_power].values_at(:measurement, :field)
      target.incomings.create!(
        measurement:, field:, value: 1, created_at: 20.minutes.ago,
      )

      expect(sensor(:inverter_power)).to include(missing: false, level: 'crit')
      expect(sensor(:inverter_power)[:age]).to be_within(5).of(20.minutes)
    end

    it 'leaves a sensor that still delivers alone' do
      measurement, field =
        SensorEnvConfig[:inverter_power].values_at(:measurement, :field)
      target.incomings.create!(measurement:, field:, value: 1)

      expect(sensor(:inverter_power)).to include(level: nil)
    end

    # An excluded sensor counts in no summary and in no badge. A red row would
    # thus report a fault that the header of the same page denies, so the row
    # reports the age like a forwarded stream.
    it 'gives an excluded sensor that stopped no colour' do
      key = SensorEnvConfig.exclude_from_house_power_keys.first
      measurement, field = SensorEnvConfig[key].values_at(:measurement, :field)
      target.incomings.create!(
        measurement:, field:, value: 1, created_at: 20.minutes.ago,
      )

      expect(sensor(key)).to include(stale: true, level: nil)
      expect(status_of(:sensors_stale)).to be_nil
    end
  end

  # A smart plug that answered three times in an hour has an average interval
  # of 20 minutes, because its own history holds the earlier outages. A rule
  # that measures the stream against that average reads a dead plug as a slow
  # one, so the page uses one fixed pair of limits instead.
  describe 'a forwarded stream that sent a few times and stopped' do
    let(:target) do
      Target.create!(influx_token: 'foo', bucket: 'test', org: 'test')
    end

    before do
      [60.minutes, 59.minutes, 20.minutes].each do |ago|
        target.incomings.create!(
          measurement: 'Shelly', field: 'power', value: 1, created_at: ago.ago,
        )
      end
    end

    it 'shows its age' do
      entry = other_measurement_fields_grouped['Shelly'].first

      expect(entry[:stale]).to be(true)
    end

    # SOLECTRUS does not read the stream, and Ingest does not know how often
    # it arrives. A stream that is slow on purpose must not look broken.
    it 'calls it no fault' do
      entry = other_measurement_fields_grouped['Shelly'].first

      expect(entry[:level]).to be_nil
      expect(status_of(:sensors_stale)).to be_nil
    end
  end

  describe '#sensor_key_for' do
    it 'names the sensor of a measurement and a field' do
      measurement, field =
        SensorEnvConfig[:inverter_power].values_at(:measurement, :field)

      expect(sensor_key_for(measurement, field)).to eq(:inverter_power)
    end

    it 'returns nothing for a field that no sensor reads' do
      expect(sensor_key_for('SENEC', 'case_temp')).to be_nil
    end
  end

  describe '#house_power_destination' do
    it 'names the measurement and the field of the result' do
      expect(house_power_destination).to eq('SENEC:house_power')
    end

    it 'returns nothing while no sensor is configured' do
      allow(SensorEnvConfig).to receive(:house_power_destination).and_return(nil)

      expect(house_power_destination).to be_nil
    end
  end

  describe '#http_status_label' do
    it 'adds the text of the status to the code' do
      expect(http_status_label(:http_response_204)).to eq('204 No Content')
    end

    it 'keeps the code alone when no text belongs to it' do
      expect(http_status_label(:http_response_299)).to eq('299')
    end
  end

  describe '#retention_hours' do
    it 'reports how long the buffer keeps a line' do
      expect(retention_hours).to eq(CleanupWorker::RETENTION.in_hours.to_i)
    end
  end

  # The cleanup runs once per interval, so the buffer holds more than the
  # retention until it runs again.
  describe '#max_range_hours' do
    it 'adds one cleanup interval to the retention' do
      expect(max_range_hours).to be > retention_hours
      expect(max_range_hours).to eq(
        (
          CleanupWorker::RETENTION + CleanupWorker::CLEANUP_INTERVAL
        ).in_hours.to_i,
      )
    end
  end

  describe '#database_size' do
    it 'returns the size of the database file' do
      expect(database_size).to be_positive
    end

    it 'returns a dash if the file does not exist' do
      allow(File).to receive(:size?).with(Database.file).and_return(nil)

      expect(database_size).to eq('–')
    end
  end

  describe '#cache_range' do
    it 'returns nil for an empty cache' do
      expect(cache_range).to be_nil
    end

    it 'returns the seconds between oldest and newest entry' do
      cache = SensorValueCache.instance
      cache.write(
        measurement: 'SENEC',
        field: 'a',
        timestamp: 1_000_000_000,
        value: 1,
      )
      cache.write(
        measurement: 'SENEC',
        field: 'b',
        timestamp: 61_000_000_000,
        value: 2,
      )

      expect(cache_range).to eq(60)
    end
  end

  describe '#queue_oldest_age' do
    it 'returns nil for an empty queue' do
      expect(queue_oldest_age).to be_nil
    end

    it 'returns the age of the oldest entry' do
      target = Target.create!(influx_token: 'foo', bucket: 'b', org: 'o')
      target.outgoings.create!(
        line_protocol: 'M f=1 1000',
        created_at: 30.seconds.ago,
      )

      expect(queue_oldest_age).to be_within(5).of(30)
    end

    # The queue grows in order, so the row with the lowest id is the oldest.
    it 'returns the age of the oldest of several entries' do
      target = Target.create!(influx_token: 'foo', bucket: 'b', org: 'o')
      target.outgoings.create!(
        line_protocol: 'M f=1 1000',
        created_at: 60.seconds.ago,
      )
      target.outgoings.create!(
        line_protocol: 'M f=2 2000',
        created_at: 30.seconds.ago,
      )

      expect(queue_oldest_age).to be_within(5).of(60)
    end

    # The badge and the field both read this, and nil does not memoize.
    it 'asks no query for an empty queue' do
      outgoing_total

      queries = count_queries { 2.times { queue_oldest_age } }

      expect(queries).to be_zero
    end

    it 'asks one query for a filled queue' do
      target = Target.create!(influx_token: 'foo', bucket: 'b', org: 'o')
      target.outgoings.create!(line_protocol: 'M f=1 1000')
      outgoing_total

      queries = count_queries { 2.times { queue_oldest_age } }

      expect(queries).to eq(1)
    end
  end

  describe '#memory_usage' do
    context 'when running on macOS' do
      before do
        allow(self).to receive_messages(macos?: true, :` => "2048\n")
      end

      it 'reads the RSS from ps' do
        expect(memory_usage).to eq(2048 * 1024)
      end
    end

    context 'when running on Linux with cgroups' do
      before do
        allow(self).to receive(:macos?).and_return(false)
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(
          '/sys/fs/cgroup/memory/memory.usage_in_bytes',
        ).and_return(true)
        allow(File).to receive(:read).and_call_original
        allow(File).to receive(:read).with(
          '/sys/fs/cgroup/memory/memory.usage_in_bytes',
        ).and_return("123456\n")
      end

      it 'reads the usage from the cgroup file' do
        expect(memory_usage).to eq(123_456)
      end
    end

    context 'when running on Linux without cgroups' do
      before do
        allow(self).to receive_messages(
          macos?: false,
          detect_cgroup_memory_path: nil,
        )
        allow(File).to receive(:read).and_call_original
        allow(File).to receive(:read).with('/proc/self/status').and_return(
          status,
        )
      end

      context 'when the status file has VmRSS' do
        let(:status) { "Name:\truby\nVmRSS:\t    2048 kB\n" }

        it 'reads the RSS from procfs' do
          expect(memory_usage).to eq(2048 * 1024)
        end
      end

      context 'when the status file has no VmRSS' do
        let(:status) { "Name:\truby\n" }

        it 'returns N/A' do
          expect(memory_usage).to eq('N/A')
        end
      end
    end
  end

  describe '#cpu_usage' do
    before { allow(self).to receive(:container_uptime).and_return(100.0) }

    context 'when running on macOS' do
      before do
        allow(self).to receive(:macos?).and_return(true)
        allow(self).to receive(:`) do |command|
          command.include?('hw.ncpu') ? "4\n" : '0:00:50'
        end
      end

      it 'derives the usage from ps' do
        expect(cpu_usage).to eq(12.5)
      end
    end

    context 'when running on Linux' do
      let(:cpuacct_usage) { nil } # cgroups v1
      let(:cpu_stat) { nil } # cgroups v2

      before do
        allow(self).to receive_messages(macos?: false, cpu_cores: 4)
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:read).and_call_original

        stub_cgroup_file('/sys/fs/cgroup/cpuacct/cpuacct.usage', cpuacct_usage)
        stub_cgroup_file('/sys/fs/cgroup/cpu.stat', cpu_stat)
      end

      # Makes `path` readable with `content`, or missing if `content` is nil
      def stub_cgroup_file(path, content)
        allow(File).to receive(:exist?).with(path).and_return(!content.nil?)
        return unless content

        allow(File).to receive(:read).with(path).and_return(content)
      end

      context 'with cgroups v1' do
        let(:cpuacct_usage) { '50000000000' }

        it 'reads the nanoseconds' do
          expect(cpu_usage).to eq(12.5)
        end
      end

      context 'with cgroups v2' do
        let(:cpu_stat) { "usage_usec 50000000\n" }

        it 'reads the microseconds' do
          expect(cpu_usage).to eq(12.5)
        end
      end

      context 'without cgroups' do
        it 'returns N/A' do
          expect(cpu_usage).to eq('N/A')
        end
      end
    end
  end

  describe '#system_uptime' do
    context 'when running on macOS' do
      before do
        allow(self).to receive_messages(
          macos?: true,
          :` => '{ sec = 1000, usec = 0 } Thu Jan  1 00:16:40 1970',
        )
      end

      it 'derives the uptime from the boot time' do
        expect(system_uptime).to eq(Time.current.to_i - 1000)
      end
    end

    context 'when running on Linux' do
      before do
        allow(self).to receive(:macos?).and_return(false)
        allow(File).to receive(:read).and_call_original
        allow(File).to receive(:read).with('/proc/uptime').and_return(
          "12345.67 98765.43\n",
        )
      end

      it 'reads the uptime from procfs' do
        expect(system_uptime).to eq(12_345.67)
      end
    end
  end

  describe '#thread_count' do
    it 'counts the running threads' do
      expect(thread_count).to be_positive
    end
  end

  describe '#disk_free' do
    it 'returns the free bytes' do
      expect(disk_free).to be_positive
    end
  end

  describe '#parse_time_to_seconds' do
    it 'parses hours, minutes and seconds' do
      expect(send(:parse_time_to_seconds, ' 1:02:03 ')).to eq(3723)
    end

    it 'parses minutes and seconds' do
      expect(send(:parse_time_to_seconds, '2:03')).to eq(123)
    end

    it 'returns 0 for an unexpected format' do
      expect(send(:parse_time_to_seconds, '')).to eq(0)
    end
  end

  describe '#cpu_cores' do
    it 'counts the cores' do
      expect(send(:cpu_cores)).to be_positive
    end

    it 'asks nproc on Linux' do
      allow(self).to receive(:macos?).and_return(false)
      allow(self).to receive(:`).with('nproc').and_return("4\n")

      expect(send(:cpu_cores)).to eq(4)
    end

    it 'falls back to a single core if the command fails' do
      allow(self).to receive(:`).and_raise(Errno::ENOENT)

      expect(send(:cpu_cores)).to eq(1)
    end
  end

  describe '#targets' do
    it 'returns nothing without a target' do
      expect(targets).to be_empty
    end

    # The token is the key to an InfluxDB. The page is behind a password, and
    # the token stays a secret behind it.
    it 'names the bucket and the org, and masks the token' do
      Target.create!(influx_token: 'super-secret', bucket: 'b', org: 'o')

      expect(targets).to eq([{ bucket: 'b', org: 'o', token: 's......t' }])
      expect(targets.to_s).not_to include('super-secret')
    end

    # Two collectors can write to one bucket with tokens of their own. The
    # rows would look the same, so the masked token tells them apart.
    it 'gives every token of a bucket a row' do
      Target.create!(influx_token: 'one', bucket: 'b', org: 'o')
      Target.create!(influx_token: 'two', bucket: 'b', org: 'o')

      expect(targets).to eq(
        [
          { bucket: 'b', org: 'o', token: 'o......e' },
          { bucket: 'b', org: 'o', token: 't......o' },
        ],
      )
    end

    # A collector that changes the precision makes a target of its own. That
    # is the same destination, and it must not appear twice.
    it 'gives one token of two precisions one row' do
      Target.create!(influx_token: 'one', bucket: 'b', org: 'o', precision: 's')
      Target.create!(influx_token: 'one', bucket: 'b', org: 'o', precision: 'ms')

      expect(targets).to eq([{ bucket: 'b', org: 'o', token: 'o......e' }])
    end

    it 'keeps the order in which the targets appeared' do
      Target.create!(influx_token: 't', bucket: 'second', org: 'o')
      Target.create!(influx_token: 't', bucket: 'first', org: 'o')

      expect(targets.map { it[:bucket] }).to eq(%w[second first])
    end
  end

  describe '#mask_token' do
    it 'keeps the first and the last character' do
      expect(mask_token('abcdefgh')).to eq('a......h')
    end

    # The number of dots is fixed, so the mask gives away no length.
    it 'gives a long and a short token the same mask' do
      expect(mask_token('ab')).to eq('a......b')
      expect(mask_token('a' * 88)).to eq('a......a')
    end

    # One character is the whole token, so the mask cannot show it twice.
    it 'shows nothing of a token that is too short' do
      expect(mask_token('a')).to eq('......')
      expect(mask_token('')).to eq('......')
      expect(mask_token(nil)).to eq('......')
    end
  end

  describe 'outgoing counters' do
    it 'has no rate before a line went out' do
      expect(outgoing_delivered).to be_zero
      expect(outgoing_delivered_rate).to be_nil
    end

    it 'turns the delivered lines into a rate per minute' do
      Stats.inc(:outgoing_delivered, 120)
      allow(self).to receive(:container_uptime).and_return(60)

      expect(outgoing_delivered_rate).to eq(120.0)
    end

    it 'reads the counters of the outbox worker' do
      Stats.inc(:outgoing_dropped, 7)
      Stats.inc(:outgoing_partial, 3)
      Stats.inc(:outgoing_failures)

      expect(outgoing_dropped).to eq(7)
      expect(outgoing_partial).to eq(3)
      expect(outgoing_failures).to eq(1)
    end

    it 'returns zero without a failure' do
      expect(outgoing_dropped).to be_zero
      expect(outgoing_partial).to be_zero
      expect(outgoing_failures).to be_zero
    end
  end

  describe 'status levels' do
    describe '#status_of' do
      it 'stays silent while every value is fine' do
        expect(status_of(:dropped)).to be_nil
        expect(status_of(:queued)).to be_nil
      end

      it 'warns about a value that passes its warn threshold' do
        Stats.inc(:outgoing_partial)

        expect(status_of(:partial)).to eq('warn')
      end

      it 'reports a lost line as critical' do
        Stats.inc(:outgoing_dropped)

        expect(status_of(:dropped)).to eq('crit')
      end

      it 'warns while the delivery cannot reach InfluxDB' do
        allow(OutboxWorker).to receive_messages(stalled: true, tried: true)

        expect(status_of(:delivery)).to eq('warn')
        expect(influx_reachability).to eq('unreachable')
      end

      # A pass over an empty queue sends no request. The page said
      # "reachable" for that case, so a fresh container reported an InfluxDB
      # that was down as good.
      it 'reports no state before the first request' do
        allow(OutboxWorker).to receive_messages(stalled: false, tried: false)

        expect(status_of(:delivery)).to be_nil
        expect(influx_reachability).to eq('not tried yet')
      end

      # A restart of InfluxDB raises the counter of failed writes, and nothing
      # lowers it again. The page stayed yellow for a fault that had cured
      # itself and left no line behind.
      it 'stays silent once the queue goes out again' do
        Stats.inc(:outgoing_failures, 3)
        allow(OutboxWorker).to receive_messages(stalled: false, tried: true)

        expect(outgoing_failures).to eq(3)
        expect(status_of(:delivery)).to be_nil
        expect(influx_reachability).to eq('reachable')
      end

      # Five old failures and two new ones are the same number, so a colour on
      # that counter says nothing about the outage of the moment.
      it 'leaves the counter of failed writes uncoloured while one fails' do
        Stats.inc(:outgoing_failures, 7)
        allow(OutboxWorker).to receive(:stalled).and_return(true)

        expect(statuses).not_to have_key(:failures)
      end

      it 'reports a range above the ceiling as critical' do
        allow(self).to receive(:incoming_range).and_return(
          (max_range_hours + 1).hours.to_i,
        )

        expect(status_of(:range)).to eq('crit')
      end

      # The cleanup runs once per interval, so the range passes the retention
      # without a fault. Red here would teach the reader to ignore red.
      it 'stays silent for a range between the retention and the ceiling' do
        allow(self).to receive(:incoming_range).and_return(
          retention_hours.hours.to_i + 30.minutes.to_i,
        )

        expect(status_of(:range)).to be_nil
      end

      it 'stays silent for a value it cannot read' do
        allow(self).to receive(:disk_free).and_return('No such file')

        expect(status_of(:disk_free)).to be_nil
      end

      it 'warns about a disk that runs low' do
        allow(self).to receive(:disk_free).and_return(StatsHelpers::GIGABYTE)

        expect(status_of(:disk_free)).to eq('warn')
      end

      it 'reports an almost full disk as critical' do
        allow(self).to receive(:disk_free).and_return(100)

        expect(status_of(:disk_free)).to eq('crit')
      end
    end

    describe '#http_error_count' do
      it 'counts every response that is not a 2xx' do
        3.times { Stats.inc(:http_response_204) }
        2.times { Stats.inc(:http_response_500) }
        Stats.inc(:http_response_400)

        expect(http_error_count).to eq(3)
      end
    end

    describe '#http_status_level' do
      it 'accepts a 2xx' do
        expect(http_status_level(:http_response_204)).to be_nil
      end

      it 'reports any other code as critical' do
        expect(http_status_level(:http_response_500)).to eq('crit')
      end
    end

    describe '#page_status' do
      it 'stays silent while every value is fine' do
        expect(page_status).to be_nil
      end

      it 'reports the worst status of the page' do
        Stats.inc(:outgoing_partial)

        expect(page_status).to eq('warn')
      end

      it 'lets a critical value win over a warning' do
        Stats.inc(:outgoing_partial)
        Stats.inc(:outgoing_dropped)

        expect(page_status).to eq('crit')
      end
    end
  end

  # What the page prints as the formula. It has to be the calculation itself,
  # not a second copy of it in the page.
  describe 'the formula' do
    let(:powers) do
      {
        inverter_power: 3000,
        grid_import_power: 500,
        battery_charging_power: 100,
      }
    end

    def record(values = powers, timestamp_ns: 1_000_000_000, source: :cache, delivered: nil)
      terms = HousePowerFormula.terms(**values)

      Stats.set(
        :house_power_last_calculation,
        {
          timestamp_ns:,
          terms:,
          result: HousePowerFormula.sum(terms),
          source:,
          delivered:,
        },
      )
    end

    describe '#formula_rows' do
      context 'with a calculation on record' do
        before { record }

        it 'prints one row per term, with its sign and its value' do
          expect(formula_rows.map { it.values_at(:sign, :key, :value) }).to eq(
            [
              ['+', :inverter_power, 3000],
              ['+', :grid_import_power, 500],
              ['−', :battery_charging_power, 100],
            ],
          )
        end

        it 'names the measurement and field behind every term' do
          expect(formula_rows.first[:source]).to eq('SENEC:inverter_power')
        end

        # The bar of a term. Without the share a reader has to compare the
        # numbers to see which sensor decides the result.
        it 'gives the largest term the full bar and the others their share' do
          expect(formula_rows.map { it[:share] }).to eq([1.0, 500 / 3000.0, 100 / 3000.0])
        end
      end

      # Integer values come straight from the cache, so a share that divides
      # them as integers is 0 for every term but the largest.
      it 'measures the share of a whole watt against the largest term' do
        record({ inverter_power: 500, grid_export_power: 100 })

        expect(formula_rows.last[:share]).to be_within(0.001).of(0.2)
      end

      it 'gives no bar while every term is zero' do
        record({ inverter_power: 0, grid_export_power: 0 })

        expect(formula_rows.map { it[:share] }).to all(be_nil)
      end

      # The page shows which sensors take part before the first calculation
      # runs, so a reader can check the configuration right after a start.
      context 'without a calculation' do
        it 'takes the terms from the configuration' do
          expect(formula_rows.map { it[:key] }).to eq(
            %i[
              inverter_power
              grid_import_power
              battery_discharging_power
              battery_charging_power
              grid_export_power
              wallbox_power
            ],
          )
        end

        # The configuration of the test environment names a total and a part.
        # The formula uses the total, so the part must not stand in the list:
        # a reader would add a value that Ingest never adds.
        it 'leaves out an inverter part while the total is configured' do
          expect(SensorEnvConfig.sensor_keys_for_house_power).to include(
            :inverter_power_1,
          )
          expect(formula_rows.map { it[:key] }).not_to include(:inverter_power_1)
        end

        it 'carries no value and no bar' do
          expect(formula_rows.map { it[:value] }).to all(be_nil)
          expect(formula_rows.map { it[:share] }).to all(be_nil)
        end
      end
    end

    describe '#formula_result' do
      it 'answers what the calculation wrote' do
        record

        expect(formula_result).to eq(3400)
      end

      it 'answers nothing without a calculation' do
        expect(formula_result).to be_nil
      end
    end

    # The formula cuts a negative sum at zero, so the result stops matching
    # the terms above it. The page has to name the number that they give.
    describe '#formula_negative_sum' do
      it 'answers the sum that the formula cut away' do
        record({ inverter_power: 100, grid_export_power: 400 })

        expect(formula_result).to eq(0)
        expect(formula_negative_sum).to eq(-300)
      end

      it 'answers nothing while the sum stands' do
        record

        expect(formula_negative_sum).to be_nil
      end
    end

    describe '#formula_timestamp' do
      it 'answers the moment the values belong to' do
        record(timestamp_ns: 1_700_000_000_000_000_000)

        expect(formula_timestamp).to eq(Time.at(1_700_000_000))
      end
    end

    # A backfill computes an old timestamp now, so the values can be older
    # than the calculation that produced them.
    describe '#formula_age' do
      it 'measures the distance to the moment the values belong to' do
        record(timestamp_ns: 60.seconds.ago.to_i * 1_000_000_000)

        expect(formula_age).to be_within(1).of(60)
      end

      it 'answers nothing without a calculation' do
        expect(formula_age).to be_nil
      end
    end

    # Ingest drops the value of the collector and writes its own in its place.
    # A result without the value it replaced says nothing about whether the
    # correction was needed.
    describe 'the delivered house power' do
      it 'answers what the collector computed itself' do
        record(delivered: 3100)

        expect(delivered_house_power).to eq(3100)
      end

      it 'names where that value came from' do
        expect(delivered_source).to eq('SENEC:house_power')
      end

      it 'answers nothing without a calculation' do
        expect(delivered_house_power).to be_nil
      end
    end

    describe '#formula_source' do
      it 'answers where the values came from' do
        record(source: :interpolator)

        expect(formula_source).to eq(:interpolator)
      end
    end

    # A sensor that the configuration keeps out cannot appear among the terms,
    # and its absence is the one thing the terms cannot explain.
    describe '#formula_excluded_keys' do
      it 'names what INFLUX_EXCLUDE_FROM_HOUSE_POWER leaves out' do
        expect(formula_excluded_keys).to eq(%i[heatpump_power])
      end
    end
  end

  # SOLECTRUS subtracts every excluded sensor from the house power again when
  # it draws the dashboard. Ingest writes one value, and a reader sees another
  # one, so the page has to show both.
  describe 'the dashboard value' do
    let(:powers) { { inverter_power: 3000, grid_export_power: 400 } }

    def record(excluded)
      terms = HousePowerFormula.terms(**powers)

      Stats.set(
        :house_power_last_calculation,
        {
          timestamp_ns: 1_000_000_000,
          terms:,
          result: HousePowerFormula.sum(terms),
          source: :cache,
          excluded:,
        },
      )
    end

    describe '#dashboard_rows' do
      it 'starts with what Ingest wrote and subtracts every excluded sensor' do
        record(heatpump_power: 600)

        expect(dashboard_rows.map { it.values_at(:sign, :key, :value) }).to eq(
          [
            ['', :house_power, 2600],
            ['−', :heatpump_power, 600],
          ],
        )
      end

      it 'names where the value of an excluded sensor comes from' do
        record(heatpump_power: 600)

        expect(dashboard_rows.last[:source]).to eq('Heatpump:power')
      end

      # Ingest writes a whole watt, and SOLECTRUS reads that one out of
      # InfluxDB. A subtraction that starts at the unrounded sum names a value
      # that the dashboard never shows.
      it 'starts at the value that Ingest wrote, not at the sum' do
        terms = HousePowerFormula.terms(inverter_power: 3000.4, grid_export_power: 400)
        Stats.set(
          :house_power_last_calculation,
          {
            timestamp_ns: 1_000_000_000,
            terms:,
            result: HousePowerFormula.sum(terms),
            source: :cache,
            excluded: { heatpump_power: 600 },
          },
        )

        expect(formula_result).to be_within(0.01).of(2600.4)
        expect(dashboard_rows.first[:value]).to eq(2600)
        expect(dashboard_result).to eq(2000)
      end

      it 'carries no value without a calculation' do
        expect(dashboard_rows.map { it[:value] }).to all(be_nil)
      end
    end

    describe '#dashboard_result' do
      it 'answers the value that the dashboard draws' do
        record(heatpump_power: 600)

        expect(dashboard_result).to eq(2000)
      end

      # Every row of the box shows a whole watt. A subtraction of the raw
      # values can miss the rows above the result by one.
      it 'subtracts the whole watts that the page shows' do
        record(heatpump_power: 599.6)

        expect(dashboard_result).to eq(2000)
      end

      # Half a subtraction is worse than none: it would name a value that the
      # dashboard never shows.
      it 'answers nothing while an excluded sensor has no value' do
        record(heatpump_power: nil)

        expect(dashboard_result).to be_nil
      end

      it 'answers nothing without a calculation' do
        expect(dashboard_result).to be_nil
      end

      it 'reports no negative difference while the result is positive' do
        record(heatpump_power: 600)

        expect(dashboard_negative_difference).to be_nil
      end

      # A wallbox that reports more power than the inverter gives makes the
      # formula cut its own sum at zero, and it stays there as long as the car
      # charges. The subtraction then reached below zero, and the page showed
      # a house that gives power back. The dashboard draws no such value.
      context 'when the formula cut its sum at zero' do
        let(:powers) do
          { inverter_power: 7570, grid_export_power: 55, wallbox_power: 7597 }
        end

        it 'cuts a negative difference at zero' do
          record(heatpump_power: 21)

          expect(written_house_power).to eq(0)
          expect(dashboard_result).to eq(0)
          expect(dashboard_negative_difference).to eq(-21)
        end
      end
    end

    # The page says why the subtraction has no result. Only a calculation
    # that ran can miss a value: before the first one the formula above says
    # that nothing is calculated yet, and a warning would contradict it.
    describe '#dashboard_subtraction_open?' do
      it 'is open while an excluded sensor has no value' do
        record(heatpump_power: nil)

        expect(dashboard_subtraction_open?).to be true
      end

      it 'is closed once the subtraction has a result' do
        record(heatpump_power: 600)

        expect(dashboard_subtraction_open?).to be false
      end

      it 'is closed before the first calculation' do
        expect(dashboard_subtraction_open?).to be_falsey
      end
    end
  end

  # The pipeline tab carries three kinds of number in one list: what holds
  # now, what the run totals, and what it averages over the uptime. The mark
  # tells the third apart from the other two.
  describe '#average' do
    it 'puts the mark in front of the value' do
      expect(average('55 /min')).to eq(
        '<span class="avg" title="Average since start">&oslash;</span>55 /min',
      )
    end
  end

  describe '#format_power' do
    it 'writes a whole watt without a decimal' do
      expect(format_power(3000)).to eq('3,000 W')
    end

    # An interpolated value lands between two samples, but Ingest writes a
    # whole watt, so the page shows a whole watt too.
    it 'rounds an interpolated value' do
      expect(format_power(1234.56)).to eq('1,235 W')
    end

    it 'drops a decimal that is zero' do
      expect(format_power(1234.0)).to eq('1,234 W')
    end

    it 'answers nothing for no value' do
      expect(format_power(nil)).to be_nil
    end
  end

  # A tab hides what it holds. The badge in the header reports every fault of
  # the page, so every fault needs a tab that points at it, otherwise a reader
  # sees a red badge and finds nothing.
  describe 'StatsHelpers::TABS' do
    it 'gives every status of the page exactly one tab' do
      assigned = StatsHelpers::TABS.flat_map { it[:statuses] }

      expect(assigned).to match_array(statuses.keys)
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
end
