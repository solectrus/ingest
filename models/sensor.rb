class Sensor < ActiveRecord::Base
  belongs_to :target

  def extracted_value
    value_int || value_float || value_bool || value_string
  end

  def mark_synced!
    update!(synced: true)
  end
end
