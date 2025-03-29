class Target < ActiveRecord::Base
  has_many :incomings, dependent: :delete_all, inverse_of: :target
  has_many :outgoings, dependent: :delete_all, inverse_of: :target

  validates :influx_token, :bucket, :org, :precision, presence: true

  PRECISION_FACTORS = {
    InfluxDB2::WritePrecision::SECOND => 1_000_000_000,
    InfluxDB2::WritePrecision::MILLISECOND => 1_000_000,
    InfluxDB2::WritePrecision::MICROSECOND => 1_000,
    InfluxDB2::WritePrecision::NANOSECOND => 1,
  }.freeze

  def timestamp_ns(timestamp)
    timestamp * PRECISION_FACTORS[precision]
  end

  def timestamp(timestamp_ns)
    timestamp_ns / PRECISION_FACTORS[precision]
  end
end
