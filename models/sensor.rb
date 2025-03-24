class Sensor < ActiveRecord::Base
  belongs_to :target, inverse_of: :sensors

  validates :measurement, :field, :timestamp, presence: true

  def value
    value_int || value_float || value_bool || value_string
  end

  def mark_synced!
    update!(synced: true)
  end
end
