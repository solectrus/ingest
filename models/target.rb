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

  def timestamp(timestamp_ns)
    case precision
    when 's'
      timestamp_ns / 1_000_000_000
    when 'ms'
      timestamp_ns / 1_000_000
    when 'us'
      timestamp_ns / 1_000
    else
      timestamp_ns
    end
  end
end
