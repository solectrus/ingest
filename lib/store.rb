require 'sequel'

class Store
  def initialize(db_url)
    @db = Sequel.sqlite(db_url)
    create_table
  end

  attr_reader :db

  def create_table
    @db.create_table? :sensor_data do
      String :measurement, null: false
      String :field, null: false
      Integer :timestamp, null: false
      Integer :value_int
      Float :value_float
      TrueClass :value_bool
      String :value_string
      primary_key %i[measurement field timestamp]
      index %i[measurement field timestamp]
    end
  end

  def save(measurement:, field:, timestamp:, value:)
    raise 'Invalid measurement or field' if measurement.nil? || field.nil?

    data = {
      measurement: measurement.to_s.strip,
      field: field.to_s.strip,
      timestamp: timestamp,
      value_int: nil,
      value_float: nil,
      value_bool: nil,
      value_string: nil,
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

    @db[:sensor_data].insert_conflict(
      target: %i[measurement field timestamp],
      update: {
        value_int: Sequel[:excluded][:value_int],
        value_float: Sequel[:excluded][:value_float],
        value_bool: Sequel[:excluded][:value_bool],
        value_string: Sequel[:excluded][:value_string],
      },
    ).insert(data)
  end

  def interpolate(measurement:, field:, target_ts:)
    ds =
      @db[:sensor_data].where(
        Sequel[:measurement] => measurement,
        Sequel[:field] => field,
      )

    prev =
      ds
        .where(Sequel[:timestamp] <= target_ts)
        .order(Sequel.desc(:timestamp))
        .first

    nxt = ds.where(Sequel[:timestamp] >= target_ts).order(:timestamp).first

    return unless prev || nxt

    prev_val = prev[:value_float] || prev[:value_int] if prev
    nxt_val = nxt[:value_float] || nxt[:value_int] if nxt

    return prev_val if prev && !nxt
    return nxt_val if nxt && !prev

    return unless prev_val && nxt_val

    if prev[:timestamp] == nxt[:timestamp]
      prev_val
    else
      t1 = prev[:timestamp]
      t2 = nxt[:timestamp]
      v1 = prev_val.to_f
      v2 = nxt_val.to_f

      v1 + ((v2 - v1) * ((target_ts - t1).to_f / (t2 - t1)))
    end
  end

  def cleanup(older_than_ts)
    @db[:sensor_data].where { timestamp < older_than_ts }.delete
  end
end
