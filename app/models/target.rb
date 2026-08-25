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

  @cache = {}
  @cache_mutex = Mutex.new

  class << self
    # A collector keeps its token, bucket, org and precision for as long as it
    # runs, so the target of a request is the same every time. The lookup
    # still ran per request, inside the transaction and the write lock. The
    # cache answers from memory and leaves that lock to the inserts.
    #
    # The mutex also makes the row unique without a retry: two threads that
    # find no row would otherwise both create one.
    def fetch(influx_token:, bucket:, org:, precision:)
      key = [influx_token, bucket, org, precision]

      @cache_mutex.synchronize do
        @cache[key] ||= find_or_create_by!(
          influx_token:,
          bucket:,
          org:,
          precision:,
        )
      end
    end

    # Drops what `fetch` has cached. The cache holds a row for as long as the
    # process runs, so whoever deletes or changes a target has to call this.
    def reset!
      @cache_mutex.synchronize { @cache.clear }
    end
  end

  def timestamp_ns(timestamp)
    timestamp * PRECISION_FACTORS[precision]
  end

  def timestamp(timestamp_ns)
    timestamp_ns / PRECISION_FACTORS[precision]
  end
end
