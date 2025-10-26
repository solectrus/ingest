class Processor
  @target : Target?

  def initialize(@influx_token : String, @bucket : String, @org : String, @precision : String)
  end

  def run(lines : Array(String))
    outbox_written = false

    lines.each do |line|
      point = Point.parse(line)

      Database.thread_safe_write do
        store_incoming(point)
        outbox_written |= enqueue_outgoing(point)
      end

      outbox_written |= trigger_house_power_if_relevant(point)
    end

    OutboxNotifier.notify! if outbox_written
  end

  private def target : Target
    @target ||= begin
      t = Target.find_by(
        influx_token: @influx_token,
        bucket: @bucket,
        org: @org,
        precision: @precision
      )

      unless t
        t = Target.new
        t.influx_token = @influx_token
        t.bucket = @bucket
        t.org = @org
        t.precision = @precision
        t.save!
      end

      t
    end
  end

  private def store_incoming(point : Point)
    now = Time.utc
    timestamp = target.timestamp_ns(point.time || now.to_unix)
    tags_json = point.tags.to_json
    created_at = now.to_s("%Y-%m-%d %H:%M:%S.%6N")

    rows = point.fields.map do |field, value|
      value_cols = value_columns(value)
      {
        :target_id    => target.id,
        :timestamp    => timestamp,
        :measurement  => point.name,
        :tags         => tags_json,
        :field        => field,
        :created_at   => created_at,
        :value_int    => value_cols[:value_int],
        :value_float  => value_cols[:value_float],
        :value_string => value_cols[:value_string],
        :value_bool   => value_cols[:value_bool],
      }
    end

    # True bulk insert with QueryBuilder (like Ruby's insert_all!)
    Incoming.bulk_insert(rows.map { |row| row.transform_values(&.as(DB::Any)) })

    # Update sensor value cache for quick lookup
    cache_values_from_rows(rows)
  end

  private def cache_values_from_rows(rows : Array(Hash(Symbol, _)))
    rows.each do |row|
      value = extract_value(row)
      next unless value

      SensorValueCache.instance.write(
        measurement: row[:measurement].to_s,
        field: row[:field].to_s,
        timestamp: row[:timestamp].as(Int64),
        value: value
      )
    end
  end

  private def value_columns(value)
    result = {
      :value_int    => nil.as(Int64?),
      :value_float  => nil.as(Float64?),
      :value_string => nil.as(String?),
      :value_bool   => nil.as(Int32?),
    }

    case value
    when Int64, Int32
      result[:value_int] = value.to_i64
    when Float64
      result[:value_float] = value
    when String
      result[:value_string] = value
    when Bool
      result[:value_bool] = value ? 1 : 0
    else
      raise ArgumentError.new("Unsupported value type: #{value.class}")
    end

    result
  end

  private def extract_value(row : Hash(Symbol, _)) : Float64?
    # We need to cache Integer and Float only
    if (v = row[:value_int]?)
      v.as(Int64).to_f64
    elsif (v = row[:value_float]?)
      v.as(Float64)
    end
  end

  private def enqueue_outgoing(point : Point) : Bool
    # Filter out the incoming house_power field (not the calculated destination)
    if (house = SensorEnvConfig[:house_power])
      if point.name == house.measurement && point.fields.has_key?(house.field)
        point.fields.delete(house.field)
        return false if point.fields.empty?
      end
    end

    outgoing = Outgoing.new
    outgoing.target_id = target.id.not_nil!
    outgoing.line_protocol = point.to_line_protocol
    outgoing.save!

    true
  end

  private def trigger_house_power_if_relevant(point : Point) : Bool
    return false unless SensorEnvConfig.relevant_for_house_power?(point)

    HousePowerCalculator.new(target).recalculate(timestamp: point.time || Time.utc.to_unix)
    true
  end
end
