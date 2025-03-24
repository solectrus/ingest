class Sensor < ActiveRecord::Base
  belongs_to :target, inverse_of: :sensors

  validates :measurement, :field, :timestamp, presence: true

  def value=(value)
    case value
    when Integer
      self.value_int = value
    when Float
      self.value_float = value
    when TrueClass, FalseClass
      self.value_bool = value
    when String
      self.value_string = value
    else
      errors.add(:value, 'Invalid value type')
    end
  end

  def value
    value_int || value_float || value_string || value_bool
  end

  def mark_synced!
    update!(synced: true)
  end

  def self.interpolate(measurement:, field:, timestamp:) # rubocop:disable Metrics/AbcSize
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

  def self.cleanup(older_than_ts = nil)
    older_than_ts ||=
      (Time.now.to_i * 1_000_000_000) - (12 * 60 * 60 * 1_000_000_000)
    Sensor.where('timestamp < ?', older_than_ts).delete_all
  end
end
