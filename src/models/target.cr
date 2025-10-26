class Target < QueryBuilder::Base
  property id : Int64?
  property bucket : String
  property org : String
  property influx_token : String
  property precision : String = "ns"

  PRECISION_FACTORS = {
    "s"  => 1_000_000_000_i64,
    "ms" => 1_000_000_i64,
    "us" => 1_000_i64,
    "ns" => 1_i64,
  }

  def initialize(@bucket = "", @org = "", @influx_token = "", @precision = "ns", @id = nil)
  end

  def timestamp_ns(timestamp : Int64) : Int64
    timestamp * PRECISION_FACTORS[precision]
  end

  def timestamp(timestamp_ns : Int64) : Int64
    timestamp_ns // PRECISION_FACTORS[precision]
  end

  def attributes_for_save : Hash(Symbol, DB::Any)
    Hash(Symbol, DB::Any){
      :bucket       => @bucket.as(DB::Any),
      :org          => @org.as(DB::Any),
      :influx_token => @influx_token.as(DB::Any),
      :precision    => @precision.as(DB::Any),
    }
  end

  # QueryBuilder overrides
  def self.table_name : String
    "targets"
  end

  def self.columns : Array(Symbol)
    [:id, :bucket, :org, :influx_token, :precision]
  end

  private def self.column_types
    {Int64, String, String, String, String}
  end

  private def self.from_tuple(id : Int64?, tuple)
    Target.new(
      bucket: tuple[1],
      org: tuple[2],
      influx_token: tuple[3],
      precision: tuple[4],
      id: tuple[0]
    )
  end
end
