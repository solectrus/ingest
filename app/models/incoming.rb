class Incoming < ActiveRecord::Base
  belongs_to :target, inverse_of: :incomings, optional: false

  validates :measurement, :field, :timestamp, presence: true
  validate :validate_value_presence

  before_validation :set_default_timestamp
  after_create :cache_sensor_value

  VALUE_COLUMNS = %i[value_int value_float value_string value_bool].freeze

  # Maps a value to the column that holds its type. `insert_all!` skips the
  # setter, so the mapping must be reachable without an instance.
  def self.value_columns(val)
    VALUE_COLUMNS.index_with(nil).tap do |result|
      case val
      when Integer               then result[:value_int] = val
      when Float                 then result[:value_float] = val
      when String                then result[:value_string] = val
      when TrueClass, FalseClass then result[:value_bool] = val
      else
        raise ArgumentError, "Unsupported value type: #{val.class}"
      end
    end
  end

  def value=(val)
    if val.nil?
      VALUE_COLUMNS.each { |column| self[column] = nil }
    else
      assign_attributes(self.class.value_columns(val))
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
    return unless value_int || value_float

    SensorValueCache.instance.write(measurement:, field:, timestamp:, value:)
  end
end
