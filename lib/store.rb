require 'sequel'

class Store
  def initialize(db_url)
    @db = Sequel.sqlite(db_url)
    create_tables
  end

  attr_reader :db

  def create_tables
    db.create_table? :targets do
      primary_key :id
      String :influx_token, null: false
      String :bucket, null: false
      String :org, null: false
      String :precision, null: false
      unique %i[influx_token bucket org precision]
    end

    db.create_table? :sensor_data do
      String :measurement, null: false
      String :field, null: false
      Integer :timestamp, null: false
      Integer :value_int
      Float :value_float
      TrueClass :value_bool
      String :value_string
      TrueClass :synced, default: false
      Integer :target_id, null: false
      foreign_key [:target_id], :targets
      primary_key %i[measurement field timestamp target_id]
      index %i[synced target_id]
    end
  end

  def save_target(influx_token:, bucket:, org:, precision: 'ns')
    existing =
      db[:targets].where(influx_token:, bucket:, org:, precision:).get(:id)
    return existing if existing

    db[:targets].insert(influx_token:, bucket:, org:, precision:)
  end

  def save(measurement:, field:, timestamp:, value:, target_id:) # rubocop:disable Metrics/AbcSize
    data = {
      measurement: measurement.to_s.strip,
      field: field.to_s.strip,
      timestamp: timestamp,
      value_int: nil,
      value_float: nil,
      value_bool: nil,
      value_string: nil,
      synced: false,
      target_id: target_id,
    }

    case value
    when Integer
      data[:value_int] = value
    when Float
      data[:value_float] = value
    when TrueClass, FalseClass
      data[:value_bool] = value
    when String
      data[:value_string] = value
    else
      raise 'Invalid value type'
    end

    db[:sensor_data].insert_conflict(
      target: %i[measurement field timestamp target_id],
      update: {
        value_int: Sequel[:excluded][:value_int],
        value_float: Sequel[:excluded][:value_float],
        value_bool: Sequel[:excluded][:value_bool],
        value_string: Sequel[:excluded][:value_string],
        synced: false,
      },
    ).insert(data)
  end

  def mark_synced(measurement:, field:, timestamp:, target_id:)
    db[:sensor_data].where(
      measurement: measurement,
      field: field,
      timestamp: timestamp,
      target_id: target_id,
    ).update(synced: true)
  end

  def interpolate(measurement:, field:, target_ts:) # rubocop:disable Metrics/AbcSize
    ds = db[:sensor_data].where(measurement: measurement, field: field)

    prev =
      ds.where { timestamp <= target_ts }.order(Sequel.desc(:timestamp)).first
    nxt = ds.where { timestamp >= target_ts }.order(:timestamp).first

    return unless prev && nxt
    return extract_value(prev) if prev[:timestamp] == nxt[:timestamp]

    t0 = prev[:timestamp]
    v0 = extract_value(prev)
    t1 = nxt[:timestamp]
    v1 = extract_value(nxt)

    v0 + ((v1 - v0) * (target_ts - t0) / (t1 - t0))
  end

  def extract_value(row)
    row[:value_int] || row[:value_float] || row[:value_bool] ||
      row[:value_string].to_f
  end

  def cleanup(older_than_ts = nil)
    older_than_ts ||=
      (Time.now.to_i * 1_000_000_000) - (12 * 60 * 60 * 1_000_000_000) # 12h in ns
    db[:sensor_data].where { timestamp < older_than_ts }.delete
  end
end
