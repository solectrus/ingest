class Incoming < ActiveRecord::Base
  belongs_to :target, inverse_of: :incomings, optional: false

  validates :measurement, :field, :timestamp, presence: true
  validate { errors.add(:value, :blank) if blank_value? }

  def blank_value?
    value_int.nil? && value_float.nil? && value_string.nil? &&
      !value_bool.in?([true, false])
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

  def self.interpolate(measurement:, field:, timestamp:) # rubocop:disable Metrics/AbcSize
    incomings = where(measurement:, field:).order(:timestamp)

    prev = incomings.where('timestamp <= ?', timestamp).last
    nxt = incomings.where('timestamp >= ?', timestamp).first

    return unless prev && nxt
    return prev.value if prev.timestamp == nxt.timestamp

    v0 = prev.value
    v1 = nxt.value
    t0 = prev.timestamp
    t1 = nxt.timestamp

    v0 + ((v1 - v0) * (timestamp - t0) / (t1 - t0))
  end

  def self.cleanup(cutoff:)
    cutoff_ns = cutoff.to_i * 1_000_000_000

    where('timestamp < ?', cutoff_ns).delete_all
  end
end
