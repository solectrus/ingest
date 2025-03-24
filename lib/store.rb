class Store
  def save_target(influx_token:, bucket:, org:, precision: 'ns')
    Target.find_or_create_by!(influx_token:, bucket:, org:, precision:)
  end

  def save_sensor(target:, measurement:, field:, timestamp:, value:)
    sensor_attrs = { measurement:, field:, timestamp:, synced: false }

    case value
    when Integer
      sensor_attrs[:value_int] = value
    when Float
      sensor_attrs[:value_float] = value
    when TrueClass, FalseClass
      sensor_attrs[:value_bool] = value
    when String
      sensor_attrs[:value_string] = value
    else
      raise 'Invalid value type'
    end

    target.sensors.create!(sensor_attrs)
  end

  def interpolate(measurement:, field:, timestamp:) # rubocop:disable Metrics/AbcSize
    sensors = Sensor.where(measurement:, field:).order(:timestamp)

    prev = sensors.where('timestamp <= ?', timestamp).last
    nxt = sensors.where('timestamp >= ?', timestamp).first

    return unless prev && nxt
    return prev.value if prev.timestamp == nxt.timestamp

    t0 = prev.timestamp
    v0 = prev.value
    t1 = nxt.timestamp
    v1 = nxt.value

    v0 + ((v1 - v0) * (timestamp - t0) / (t1 - t0))
  end

  def cleanup(older_than_ts = nil)
    older_than_ts ||=
      (Time.now.to_i * 1_000_000_000) - (12 * 60 * 60 * 1_000_000_000)
    Sensor.where('timestamp < ?', older_than_ts).delete_all
  end
end
