class Target < ActiveRecord::Base
  has_many :sensors, dependent: :destroy

  validates :influx_token, :bucket, :org, :precision, presence: true
end
