class Incoming < ActiveRecord::Base
  belongs_to :target, inverse_of: :incomings, optional: false

  validates :measurement, :field, :timestamp, presence: true
  validate :validate_value_presence

  before_validation :set_default_timestamp
  after_create :cache_sensor_value

  def value=(val)
    self.value_int = nil
    self.value_float = nil
    self.value_string = nil
    self.value_bool = nil
    return if val.nil?

    case val
    when Integer
      self.value_int = val
    when Float
      self.value_float = val
    when TrueClass, FalseClass
      self.value_bool = val
    when String
      self.value_string = val
    else
      raise ArgumentError, "Unsupported value type: #{val.class}"
    end
  end

  def value
    return value_int unless value_int.nil?
    return value_float unless value_float.nil?
    return value_string unless value_string.nil?
    return value_bool unless value_bool.nil?

    nil
  end

  private

  def validate_value_presence
    errors.add(:value, :blank) if value.nil?
  end

  def set_default_timestamp
    self.timestamp ||= target.timestamp_ns(Time.current.to_i)
  end

  def cache_sensor_value
    SensorValueCache.instance.write(measurement:, field:, timestamp:, value:)
  end
end
