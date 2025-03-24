class Target < ActiveRecord::Base
  has_many :sensors, dependent: :destroy, inverse_of: :target

  validates :influx_token, :bucket, :org, :precision, presence: true
end
