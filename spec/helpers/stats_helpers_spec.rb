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

  describe '#stale_level' do
    it 'accepts a stream that sent within five minutes' do
      expect(stale_level(4.minutes)).to be_nil
    end

    it 'reports a stream that is late' do
      expect(stale_level(6.minutes)).to eq('warn')
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

  describe '#house_power_inputs' do
    # The configuration excludes the heat pump, and the house power itself is
    # the result, not an input.
    it 'counts the sensors of the formula' do
      expect(house_power_inputs).to eq(
        SensorEnvConfig.sensor_keys_for_house_power.size,
      )
      expect(house_power_inputs).to be < SensorEnvConfig.config.size
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
        (CleanupWorker::RETENTION + CleanupWorker::CLEANUP_INTERVAL).in_hours.to_i,
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

    # The token is a secret. The page needs a password only, so it must not
    # carry the token of an InfluxDB.
    it 'names the bucket and the org, never the token' do
      Target.create!(influx_token: 'super-secret', bucket: 'b', org: 'o')

      expect(targets).to eq([{ bucket: 'b', org: 'o', tokens: 1 }])
      expect(targets.to_s).not_to include('super-secret')
    end

    # Two collectors can write to one bucket with tokens of their own. The
    # rows would look the same, so the count of the tokens tells them apart.
    it 'counts the tokens of a bucket' do
      Target.create!(influx_token: 'one', bucket: 'b', org: 'o')
      Target.create!(influx_token: 'two', bucket: 'b', org: 'o')

      expect(targets).to eq([{ bucket: 'b', org: 'o', tokens: 2 }])
    end

    # A collector that changes the precision makes a target of its own. That
    # is the same token, and it must not count twice.
    it 'counts one token of two precisions once' do
      Target.create!(influx_token: 'one', bucket: 'b', org: 'o', precision: 's')
      Target.create!(influx_token: 'one', bucket: 'b', org: 'o', precision: 'ms')

      expect(targets).to eq([{ bucket: 'b', org: 'o', tokens: 1 }])
    end

    it 'keeps the order in which the targets appeared' do
      Target.create!(influx_token: 't', bucket: 'second', org: 'o')
      Target.create!(influx_token: 't', bucket: 'first', org: 'o')

      expect(targets.map { it[:bucket] }).to eq(%w[second first])
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

      it 'reports a range above the retention as critical' do
        allow(self).to receive(:incoming_range).and_return(
          (max_range_hours + 1).hours.to_i,
        )

        expect(status_of(:range)).to eq('crit')
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
end
