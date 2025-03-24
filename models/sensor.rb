class Sensor < ActiveRecord::Base
  belongs_to :target, inverse_of: :sensors

  validates :measurement, :field, :timestamp, presence: true

  validate do
    next if value_int || value_float || value_string
    next if value_bool.in?([true, false])

    errors.add(:value, :blank)
  end

  def value=(val)
    case val
    when Integer
      self.value_int = val
    when Float
      self.value_float = val
    when TrueClass, FalseClass
      self.value_bool = val
    when String
      self.value_string = val
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

    v0 = prev.value
    v1 = nxt.value
    t0 = prev.timestamp
    t1 = nxt.timestamp

    v0 + ((v1 - v0) * (timestamp - t0) / (t1 - t0))
  end

  def self.cleanup(hours: 12)
    cutoff = (Time.now.to_i - (hours * 3600)) * 1_000_000_000

    where('timestamp < ?', cutoff).delete_all
  end
end
