class Target < ActiveRecord::Base
  has_many :sensors, dependent: :destroy, inverse_of: :target

  validates :influx_token, :bucket, :org, :precision, presence: true

  def timestamp_ns(timestamp)
    case precision
    when 's'
      timestamp * 1_000_000_000
    when 'ms'
      timestamp * 1_000_000
    when 'us'
      timestamp * 1_000
    else
      timestamp
    end
  end
end
