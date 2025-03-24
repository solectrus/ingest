class Target < ActiveRecord::Base
  PRECISION_FACTOR = {
    's' => 1,
    'ms' => 1_000,
    'us' => 1_000_000,
    'ns' => 1_000_000_000,
  }.freeze

  has_many :sensors, dependent: :destroy, inverse_of: :target

  validates :influx_token, :bucket, :org, :precision, presence: true
end
