START_TIME = Time.current

module StatsHelpers # rubocop:disable Metrics/ModuleLength
  # What arrives, per measurement and field: how many lines, and the row that
  # brought the last one. The page needs both, for the total, for the sensor
  # list and for the measurement cards. One scan answers them.
  #
  # It asks for MAX(id) and not for MAX(created_at), and the difference is
  # large. SQLite holds the rowid in every index, and `id` is the rowid, so
  # the scan reads the index alone. `created_at` is not in the index, and the
  # scan then reads the table row of every line: 369ms against 73ms on a
  # buffer of 800,000 lines. The ids go to #last_arrivals, which reads about
  # 60 rows by primary key.
  #
  # The queue grows in order, so the highest id of a group carries its newest
  # time.
  INCOMING_COLUMNS = <<~SQL.squish
    measurement,
    field,
    COUNT(*) AS count,
    MAX(id) AS id
  SQL

  def incoming_total
    @incoming_total ||= incoming_counts.values.sum
  end

  def outgoing_total
    @outgoing_total ||= Outgoing.count
  end

  # Where the lines go. A collector that sends a different bucket, org or token
  # makes a target of its own, so a row that nobody expects means that
  # somebody writes elsewhere.
  #
  # Two collectors can write to the same bucket with different tokens. Such
  # targets share a row, and the count of the tokens tells them apart.
  #
  # The token itself stays out of the answer. It is a secret, and the page
  # needs only a password.
  TARGET_COLUMNS = <<~SQL.squish
    bucket,
    org,
    COUNT(DISTINCT influx_token) AS tokens
  SQL

  def targets
    @targets ||=
      Target
        .group(:bucket, :org)
        .order(Arel.sql('MIN(id)'))
        .pluck(Arel.sql(TARGET_COLUMNS))
        .map { |bucket, org, tokens| { bucket:, org:, tokens: } }
  end

  # Lines that reached InfluxDB. The queue length alone does not say whether it
  # drains: a queue of 500,000 looks the same while it falls and while it
  # stands still.
  def outgoing_delivered
    Stats.counter(:outgoing_delivered)
  end

  def outgoing_delivered_rate
    return unless outgoing_delivered.positive?

    60.0 * outgoing_delivered / container_uptime
  end

  # The same measure as the incoming values, on the other side of the buffer.
  # The two numbers do not have to match: the incoming house power is dropped,
  # and the calculated one takes its place.
  def outgoing_delivered_values
    Stats.counter(:outgoing_delivered_values)
  end

  def outgoing_delivered_values_rate
    return unless outgoing_delivered_values.positive?

    60.0 * outgoing_delivered_values / container_uptime
  end

  # InfluxDB refused these lines for good, so they are gone. Only the log knew
  # about it before.
  def outgoing_dropped
    Stats.counter(:outgoing_dropped)
  end

  # InfluxDB answered a batch of these lines with a 422. It stored the points
  # it could and named the rest in the error text only, so the number counts
  # the lines of the batch, not the points it refused.
  def outgoing_partial
    Stats.counter(:outgoing_partial)
  end

  # InfluxDB could not be reached. The lines stay in the queue and go out
  # again on the next pass.
  def outgoing_failures
    Stats.counter(:outgoing_failures)
  end

  def skipped_lines
    Stats.counter(LineBatch::SKIPPED_STAT)
  end

  def calculation_count
    @calculation_count ||= Stats.counter(:house_power_recalculates)
  end

  def value_or_dash(value)
    return '–' if value.nil?

    block_given? ? yield(value) : value
  end

  def calculation_rate
    return unless calculation_count.positive?

    60.0 * calculation_count / container_uptime
  end

  # A backfill asks for older timestamps than the cache holds, so it misses
  # every time. The queries show what those misses cost.
  def interpolate_queries
    @interpolate_queries ||= Stats.counter(:interpolate_queries)
  end

  # What a miss costs. The misses of one request share a single query, so this
  # ratio stays near or below 1, whatever the hit rate is. It is the number to
  # watch, not the hit rate.
  def interpolate_queries_per_request
    requests = Stats.counter(:http_requests)
    return unless requests.positive?

    interpolate_queries / requests.to_f
  end

  # The cache holds the newest value of a sensor only. It can thus answer the
  # newest timestamp of a batch and no other one, because an older timestamp
  # needs a value that the newer one already replaced.
  #
  # The hit rate is therefore about 1 divided by the number of timestamps per
  # batch. A collector that sends 5 timestamps per request gives 20 percent,
  # and that is correct behaviour, not a fault. Read the rate as a measure of
  # how dense the batches are. To see the cost, read the queries per request.
  def calculation_cache_hits
    return unless calculation_count.positive?

    100.0 * Stats.counter(:house_power_recalculate_cache_hits) / calculation_count
  end

  def calculation_skipped
    return unless calculation_count.positive?

    100.0 * Stats.counter(:house_power_recalculate_skipped) / calculation_count
  end

  # How many skipped calculations missed each sensor. One skipped calculation
  # can miss more than one sensor, and it counts each of them. The numbers
  # thus add up to more than the number of skips.
  def calculation_skips_by_sensor
    prefix = HousePowerCalculator::SKIP_STAT_PREFIX
    Stats
      .counters_by(prefix)
      .transform_keys { |key| key.to_s.delete_prefix(prefix) }
      .sort_by { |_, count| -count }
  end

  def last_calculation_age
    timestamp = Stats.value(:house_power_last_success_at)
    age_from(Time.at(timestamp)) if timestamp
  end

  def response_time
    return unless Stats.counter(:http_requests).positive?

    (Stats.sum(:http_duration_total) / Stats.counter(:http_requests)).round
  end

  # How long ago the server measured something. It does not grow while the page
  # stands.
  #
  # The script counted these values up before, second by second. That made
  # them disagree with every other value of the page, because those keep the
  # moment of the request: the age of the last line ran ahead while the
  # throughput and the counts stood still. One moment for the whole page reads
  # better than one field that is right. The header says how old that moment
  # is.
  def format_age(seconds)
    "#{format_duration(seconds)} ago"
  end

  def format_duration(seconds) # rubocop:disable Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
    return '–' unless seconds

    time = Time.at(seconds).utc
    days = time.day - 1
    hours = time.hour
    minutes = time.min
    seconds = time.sec

    [
      ("#{days}d" if days.positive?),
      ("#{hours}h" if hours.positive? || days.positive?),
      ("#{minutes}m" if minutes.positive? || hours.positive?),
      ("#{seconds}s" if days.zero? && hours.zero?),
    ].compact.join(' ')
  end

  def database_size
    size_bytes = File.size?(Database.file)
    return '–' unless size_bytes

    size_bytes
  rescue StandardError => e
    # simplecov:disable
    e.message
    # simplecov:enable
  end

  # Every sensor of the configuration that has no line in the buffer. A typo in
  # an INFLUX_SENSOR_* variable and a collector that does not send look the
  # same on the page otherwise: the sensor is simply absent from the list of
  # measurements, and a reader has to compare that list against the
  # configuration by hand.
  #
  # The buffer holds the retention period only, so a sensor that stopped
  # before it appears here too. That is the point.
  #
  # A sensor that the house power excludes stays out of the list. The
  # configuration says that Ingest must not use it, and an alarm about a
  # sensor that nobody wants is a false alarm.
  def sensors_without_data
    @sensors_without_data ||= find_sensors_without_data
  end

  # The whole sensor configuration, each entry with what arrives for it. The
  # page lists every configured sensor, not the missing ones alone: a reader
  # can then tell a sensor that nobody sends from one that is not configured.
  def configured_sensors
    @configured_sensors ||= SensorEnvConfig.config.map { configured_sensor(*it) }
  end

  # Every configured sensor that the page watches for a fault. The excluded
  # ones stay out: the configuration says that Ingest must not use them.
  def included_sensors
    @included_sensors ||= configured_sensors.reject { it[:excluded] }
  end

  # What INFLUX_EXCLUDE_FROM_HOUSE_POWER leaves out. The page keeps these
  # sensors apart from the others, because a missing value means something
  # different here: the house power does not wait for it.
  def excluded_sensors
    @excluded_sensors ||= configured_sensors.select { it[:excluded] }
  end

  # Every configured sensor that arrived once and then stopped. The buffer
  # keeps the lines of a dead collector for the whole retention period, so the
  # count, the time span and the throughput of the sensor all keep the value
  # they had while it ran. Only the age of its last line falls behind.
  #
  # This is the case that #sensors_without_data cannot see: the sensor has
  # data, and it is old.
  def stale_sensors
    @stale_sensors ||= included_sensors.select { it[:level] }
  end

  # The one line above the sensor list. It has to name two faults apart,
  # because they need different repairs. A sensor without data points at the
  # INFLUX_SENSOR_* variable, a stale sensor at the collector that stopped.
  #
  # It returns nothing while every sensor delivers, and the page then says so
  # in its own words.
  def sensors_summary
    total = included_sensors.size
    parts = []
    parts << "#{sensors_without_data.size} of #{total} without data" if sensors_without_data.any?
    parts << "#{stale_sensors.size} of #{total} stale" if stale_sensors.any?

    parts.join(', ').presence
  end

  def sensors_summary_level
    worst_level([status_of(:sensors_without_data), status_of(:sensors_stale)])
  end

  # The sensor key that a measurement and a field belong to. The cards list
  # what arrives, and the key says which of those lines SOLECTRUS reads.
  def sensor_key_for(measurement, field)
    sensor_keys_by_target[[measurement, field]]
  end

  # Where the calculated house power goes. Without it a reader cannot tell
  # whether the result overwrites the value of the collector or goes to a
  # field of its own.
  def house_power_destination
    destination = SensorEnvConfig.house_power_destination
    return unless destination

    "#{destination[:measurement]}:#{destination[:field]}"
  end

  # "204" alone makes the reader look the code up.
  def http_status_label(key)
    code = key.to_s.delete_prefix('http_response_')
    text = Rack::Utils::HTTP_STATUS_CODES[code.to_i]

    text ? "#{code} #{text}" : code
  end

  # Everything that arrives and is not a configured sensor. Ingest forwards it
  # unchanged, and the list is the only place that names it. A configured
  # sensor stays out: it stands in the list of sensors above, with the same
  # throughput, and one number in two places invites a comparison that has
  # nothing to say.
  def other_measurement_fields_grouped
    @other_measurement_fields_grouped ||=
      incoming_by_target
        .filter_map { |target, entry| other_stream(target, entry) }
        .group_by { |entry| entry[:measurement] }
        .sort_by { |measurement, groups| [-groups.size, measurement] }
        .to_h
  end

  # The queue grows in order, so the row with the lowest id carries the oldest
  # time. MIN(created_at) has no index and scans the whole table: 37ms against
  # 0.6ms on a queue of 1,000,000 rows.
  #
  # An empty queue has no oldest row, and `||=` keeps no nil. The badge and the
  # field both read this, so the query ran twice while the queue was empty. The
  # count is memoized and comes first, so it can answer that case alone.
  def queue_oldest_age
    return if outgoing_total.zero?

    @queue_oldest_age ||= age_from(Outgoing.order(:id).pick(:created_at))
  end

  # An empty buffer has no oldest row, and `||=` keeps no nil. The counts come
  # from one scan that the page makes anyway, so they answer that case without
  # a query of their own.
  def incoming_oldest
    return if incoming_counts.empty?

    @incoming_oldest ||= Incoming.minimum(:created_at)
  end

  # The newest line of the whole buffer. #incoming_by_target already carries
  # the newest time of every measurement and field, and the newest of those is
  # the newest of all. The page thus needs no MAX(created_at) of its own.
  #
  # A row can go away between the two queries of that scan, and its time is
  # then absent. The remaining ones still give the answer.
  def incoming_newest
    @incoming_newest ||=
      incoming_by_target.each_value.filter_map { it[:last_at] }.max
  end

  def incoming_range
    @incoming_range ||= range_between(incoming_oldest, incoming_newest)
  end

  # Lines that arrived and were stored. The buffer holds a row per field, so a
  # line of 26 fields counts 26 there. Only this number compares with the
  # delivered lines, and both count since the start of the container.
  def incoming_lines
    Stats.counter(:incoming_lines)
  end

  def incoming_lines_rate
    return unless incoming_lines.positive?

    60.0 * incoming_lines / container_uptime
  end

  # One measured value, one field. A line carries as many values as it has
  # fields, so the number of lines says little about the load: one collector
  # sends 26 fields in one line, the next one sends 1 field per line.
  #
  # This counter and the buffer count the same thing. The buffer holds the
  # retention period only, so it cannot answer how much arrived since the
  # start.
  def incoming_values
    Stats.counter(:incoming_values)
  end

  def incoming_values_rate
    return unless incoming_values.positive?

    60.0 * incoming_values / container_uptime
  end

  # How long ago the last line arrived. Without it a page of an ingest that
  # nobody feeds looks healthy: the total, the range and the throughput all
  # keep their value while no collector sends.
  def incoming_age
    @incoming_age ||= age_from(incoming_newest)
  end

  def cache_range
    @cache_range ||=
      range_between(
        cache_stats[:oldest_timestamp]&./(1_000_000_000),
        cache_stats[:newest_timestamp]&./(1_000_000_000),
      )
  end

  def cache_size
    @cache_size ||= cache_stats[:size]
  end

  def cache_stats
    @cache_stats ||= SensorValueCache.instance.stats
  end

  def incoming_throughput_for(count)
    return unless incoming_range&.positive?

    (60.0 * count / incoming_range).round(1)
  end

  # How long the buffer keeps a line. It explains the ceiling of the incoming
  # time span, and it says how far back a restart can replay.
  def retention_hours
    CleanupWorker::RETENTION.in_hours.to_i
  end

  # The cleanup deletes what is older than the retention, but it runs once per
  # interval. The range thus goes above the retention before the next cleanup
  # cuts it back.
  #
  # Two intervals, not one: the worker sleeps first, so a restart shortly
  # before a cleanup delays that cleanup by a full interval. A restart is
  # normal, and the buffer survives it on disk. Only above this ceiling did a
  # cleanup really fail.
  def max_range_hours
    (
      CleanupWorker::RETENTION + (2 * CleanupWorker::CLEANUP_INTERVAL)
    ).in_hours.to_i
  end

  GIGABYTE = 1024**3

  # One place decides what counts as a problem. The badge in the header and the
  # fields of the page read the same source, so the two cannot disagree.
  #
  # The average response time and the CPU usage have no entry on purpose. Both
  # divide by the container uptime, so a backfill right after a start pushes
  # them up and they fall back on their own. A field that turns red without a
  # fault teaches the reader to ignore red.
  def statuses # rubocop:disable Metrics/AbcSize
    @statuses ||= {
      incoming_age: stale_level(incoming_age),
      sensors_without_data: level(sensors_without_data.size, warn: 1),
      sensors_stale: worst_level(stale_sensors.map { it[:level] }),
      queued: level(outgoing_total, warn: 1_000, crit: 10_000),
      queue_age: level(queue_oldest_age, warn: 1.minute, crit: 10.minutes),
      dropped: level(outgoing_dropped, crit: 1),
      partial: level(outgoing_partial, warn: 1),
      failures: level(outgoing_failures, warn: 1),
      skipped_lines: level(skipped_lines, crit: 1),
      skipped_stale: level(calculation_skipped, warn: 5, crit: 25),
      last_success: level(last_calculation_age, warn: 5.minutes, crit: 30.minutes),
      http_errors: level(http_error_count, crit: 1),
      range: level(incoming_range, crit: max_range_hours.hours),
      disk_free: level_below(disk_free, warn: 2 * GIGABYTE, crit: GIGABYTE / 2),
    }
  end

  # Not `status`: Sinatra defines that one to set the response status, and
  # `redirect` calls it.
  def status_of(key)
    statuses[key]
  end

  # The worst status of the page. It colours the badge in the header.
  def page_status
    worst_level(statuses.values)
  end

  def worst_level(levels)
    return 'crit' if levels.include?('crit')
    return 'warn' if levels.include?('warn')

    nil
  end

  # A response that is not a 2xx means the collector got an error back.
  def http_error_count
    @http_error_count ||=
      Stats
        .counters_by(:http_response)
        .sum { |key, count| http_status_ok?(key) ? 0 : count }
  end

  def http_status_ok?(key)
    (200..299).cover?(key.to_s.delete_prefix('http_response_').to_i)
  end

  def http_status_level(key)
    'crit' unless http_status_ok?(key)
  end

  # When a stream is quiet for long enough that its rate says nothing about
  # the present. The page uses one limit for every stream, the same limit that
  # the newest line of the whole buffer uses.
  #
  # It is the limit of HousePowerCalculator::MAX_SENSOR_AGE_NS. A sensor that
  # is older gives no value to the house power, so this is the moment when the
  # silence starts to hurt.
  #
  # One limit, not two. A middle stage at five minutes marked a collector that
  # sends every ten minutes as late, and a colour that is wrong that often
  # teaches the reader to ignore it.
  #
  # A rule that measures a stream against its own history looks better and
  # fails. A smart plug that answered three times in an hour has an average
  # interval of 20 minutes, because its own history holds the earlier outages.
  # Such a rule reads a dead plug as a slow one and stays quiet.
  STALE_LIMIT = 15.minutes

  def stale?(age)
    stale_level(age).present?
  end

  def stale_level(age)
    level(age, crit: STALE_LIMIT)
  end

  # What the last column of a stream says. A quiet stream shows the age of its
  # last line instead of its rate. The rate of a quiet stream is an average
  # over the whole buffer, and it keeps the value it had while the stream ran,
  # so it reads as healthy for the whole retention period. Only the age says
  # that nothing arrives now.
  #
  # The colour comes from the entry, and only a configured sensor carries one.
  # A forwarded stream can be slow on purpose: the tibber-collector sends once
  # an hour, and the forecast-collector every 15 to 60 minutes. Ingest does
  # not know the cadence of such a stream, so it reports the age and leaves
  # the judgement to the reader.
  def stream_tag(entry)
    return throughput_tag(entry[:throughput]) unless entry[:stale]

    css_class = %( class="#{entry[:level]}") if entry[:level]

    %(<small#{css_class}>#{format_age(entry[:age])}</small>)
  end

  # SOLECTRUS does not use data that arrives faster than every 4 seconds. A
  # higher rate fills the buffer and gives no gain.
  THROUGHPUT_WARN = 60 / 4
  THROUGHPUT_CRIT = 2 * THROUGHPUT_WARN

  def throughput_tag(value)
    return '<small>-</small>' unless value

    css_class =
      if value <= THROUGHPUT_WARN
        'ok'
      elsif value <= THROUGHPUT_CRIT
        'warn'
      else
        'crit'
      end

    "<small class=\"#{css_class}\">#{format_rate(value)}</small>"
  end

  # A rate of 10 and above needs no decimal: the reader wants the size, not the
  # tenth. Below 10 the decimal carries the message, because a rate that rounds
  # to 0 reads as "nothing arrives".
  def rate_number(value)
    rounded = value.round(1)
    rounded >= 10 ? value.round : rounded
  end

  def format_rate(value)
    return unless value

    "#{number_to_delimited(rate_number(value))} /min"
  end

  def memory_usage
    return rss_from_ps_macos if macos?

    # Prefer cgroup usage if available (Docker etc.)
    if (cgroup_path = detect_cgroup_memory_path)
      return File.read(cgroup_path).to_i
    end

    # Fallback for LXC: /proc/self/status
    rss_from_procfs || 'N/A'
  rescue StandardError => e
    # simplecov:disable
    e.message
    # simplecov:enable
  end

  def cpu_usage # rubocop:disable Metrics/AbcSize
    cpu_seconds =
      if macos?
        time_str = `ps -o time= -p #{Process.pid}`.strip
        parse_time_to_seconds(time_str)
      elsif File.exist?('/sys/fs/cgroup/cpuacct/cpuacct.usage') # cgroup v1
        ns = File.read('/sys/fs/cgroup/cpuacct/cpuacct.usage').to_i
        ns / 1_000_000_000.0
      elsif File.exist?('/sys/fs/cgroup/cpu.stat') # cgroup v2
        usec =
          File.read('/sys/fs/cgroup/cpu.stat')[/usage_usec\s+(\d+)/, 1].to_i
        usec / 1_000_000.0
      else
        return 'N/A'
      end

    total_percent = (cpu_seconds / container_uptime) * 100
    total_percent / cpu_cores
  rescue StandardError => e
    # simplecov:disable
    e.message
    # simplecov:enable
  end

  def container_uptime
    @container_uptime ||= age_from(START_TIME)
  end

  def system_uptime
    @system_uptime ||=
      if macos?
        boot = `sysctl -n kern.boottime`.scan(/\d+/).first.to_i
        Time.current.to_i - boot
      else
        File.read('/proc/uptime').to_f
      end
  rescue StandardError => e
    # simplecov:disable
    e.message
    # simplecov:enable
  end

  def thread_count
    Thread.list.count
  end

  # `df` forks a process, and the page asks twice: once for the badge and once
  # for the field. One call per request is enough.
  def disk_free
    @disk_free ||=
      begin
        available_kb = `df -k /`.lines[1].split[3].to_i
        available_kb * 1024
      rescue StandardError => e
        # simplecov:disable
        e.message
        # simplecov:enable
      end
  end

  private

  # The CSS class of a value that gets worse as it grows.
  def level(value, warn: nil, crit: nil)
    return unless value.is_a?(Numeric)
    return 'crit' if crit && value >= crit
    return 'warn' if warn && value >= warn

    nil
  end

  # The CSS class of a value that gets worse as it falls.
  def level_below(value, warn:, crit:)
    return unless value.is_a?(Numeric)
    return 'crit' if value <= crit
    return 'warn' if value <= warn

    nil
  end

  # An empty buffer would report every sensor, which says nothing. The age of
  # the newest line covers that case.
  def find_sensors_without_data
    return [] if incoming_counts.empty?

    SensorEnvConfig.config.filter_map do |key, sensor|
      next if excluded_from_house_power?(key)

      pair = [sensor[:measurement], sensor[:field]]
      [key, pair.join(':')] unless incoming_counts.key?(pair)
    end
  end

  # One entry of the sensor list. A sensor without a line of its own carries
  # no number, and `missing` says whether that is a fault: while the buffer is
  # empty it marks every sensor, and that says nothing.
  def configured_sensor(key, sensor)
    entry = incoming_by_target[[sensor[:measurement], sensor[:field]]]
    age = age_from(entry&.fetch(:last_at))

    {
      key:,
      target: "#{sensor[:measurement]}:#{sensor[:field]}",
      throughput: (incoming_throughput_for(entry[:count]) if entry),
      age:,
      stale: stale?(age),
      level: stale_level(age),
      missing: entry.nil? && incoming_by_target.any?,
      excluded: excluded_from_house_power?(key),
      # Ingest calculates the house power from the other sensors, so the list
      # marks it as the result of the formula and not as a term of it.
      result: key == :house_power,
    }
  end

  # Whether the house power ignores this sensor.
  # INFLUX_EXCLUDE_FROM_HOUSE_POWER names the sensors it leaves out. The house
  # power is the result of the formula and never an input, so the variable
  # cannot exclude it.
  def excluded_from_house_power?(key)
    key != :house_power &&
      SensorEnvConfig.exclude_from_house_power_keys.include?(key)
  end

  # One entry of the list of forwarded streams, or nothing for a stream that a
  # configured sensor reads. Such a stream carries no level: SOLECTRUS does
  # not read it, and Ingest does not know how often it arrives.
  def other_stream((measurement, field), entry)
    return if sensor_key_for(measurement, field)

    age = age_from(entry[:last_at])

    {
      measurement:,
      field:,
      throughput: incoming_throughput_for(entry[:count]),
      age:,
      stale: stale?(age),
    }
  end

  def sensor_keys_by_target
    @sensor_keys_by_target ||=
      SensorEnvConfig.config.to_h do |key, sensor|
        [[sensor[:measurement], sensor[:field]], key]
      end
  end

  # Everything the page knows about what arrives. One scan of the index
  # answers the total, the sensor list and the measurement cards together.
  def incoming_by_target
    @incoming_by_target ||=
      begin
        rows = Incoming.group(:measurement, :field).pluck(Arel.sql(INCOMING_COLUMNS))
        times = last_arrivals(rows.map(&:last))

        rows.to_h do |measurement, field, count, id|
          [[measurement, field], { count:, last_at: times[id] }]
        end
      end
  end

  # The time of each newest line, by primary key. The list holds one id per
  # measurement and field, so this reads a few dozen rows.
  def last_arrivals(ids)
    Incoming.where(id: ids).pluck(:id, :created_at).to_h
  end

  def incoming_counts
    @incoming_counts ||= incoming_by_target.transform_values { it[:count] }
  end

  def macos?
    RUBY_PLATFORM.include?('darwin')
  end

  def age_from(time)
    (Time.current - time).clamp(0, Float::INFINITY) if time
  end

  def range_between(start_time, end_time)
    end_time - start_time if start_time && end_time
  end

  def parse_time_to_seconds(str)
    parts = str.strip.split(':').map(&:to_i)
    case parts.size
    when 3
      (parts[0] * 3600) + (parts[1] * 60) + parts[2]
    when 2
      (parts[0] * 60) + parts[1]
    else
      0
    end
  end

  def cpu_cores
    macos? ? `sysctl -n hw.ncpu`.to_i : `nproc`.to_i
  rescue StandardError
    1
  end

  def detect_cgroup_memory_path
    paths = [
      '/sys/fs/cgroup/memory/memory.usage_in_bytes', # cgroups v1
      '/sys/fs/cgroup/memory.current', # cgroups v2
    ]
    paths.find { |p| File.exist?(p) }
  end

  def rss_from_procfs
    status = File.read('/proc/self/status')
    if (match = status.match(/^VmRSS:\s+(\d+)\s+kB/))
      match[1].to_i * 1024
    end
  end

  def rss_from_ps_macos
    rss_kb = `ps -o rss= -p #{Process.pid}`.lines.last.to_i
    rss_kb * 1024
  end
end
