class Incoming < ActiveRecord::Base
  belongs_to :target, inverse_of: :incomings, optional: false

  validates :measurement, :field, :timestamp, presence: true
  validate { errors.add(:value, :blank) if blank_value? }

  def blank_value?
    value_int.nil? && value_float.nil? && value_string.nil? &&
      !value_bool.in?([true, false])
  end

  before_validation do
    self.timestamp ||= target.timestamp_ns(Time.current.to_i)
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

  def self.cleanup(cutoff:)
    cutoff_ns = cutoff.to_i * 1_000_000_000

    DBConfig.thread_safe_db_write do
      where('timestamp < ?', cutoff_ns).delete_all
    end
  end
end
