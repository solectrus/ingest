class Target < ActiveRecord::Base
  has_many :incomings, dependent: :delete_all, inverse_of: :target
  has_many :outgoings, dependent: :delete_all, inverse_of: :target

  validates :influx_token, :bucket, :org, :precision, presence: true

  PRECISION_FACTORS = {
    's' => 1_000_000_000,
    'ms' => 1_000_000,
    'us' => 1_000,
    'ns' => 1,
  }.freeze

  def timestamp_ns(timestamp)
    timestamp * PRECISION_FACTORS[precision]
  end

  def timestamp(timestamp_ns)
    timestamp_ns / PRECISION_FACTORS[precision]
  end
end
