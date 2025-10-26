class Outgoing < QueryBuilder::Base
  property id : Int64?
  property target_id : Int64
  property line_protocol : String
  property created_at : String

  def initialize(
    @target_id = 0_i64,
    @line_protocol = "",
    @created_at = Time.utc.to_s("%Y-%m-%d %H:%M:%S.%6N"),
    @id = nil,
  )
  end

  def attributes_for_save : Hash(Symbol, DB::Any)
    @created_at = Time.utc.to_s("%Y-%m-%d %H:%M:%S.%6N") unless @id

    Hash(Symbol, DB::Any){
      :target_id     => @target_id.as(DB::Any),
      :line_protocol => @line_protocol.as(DB::Any),
      :created_at    => @created_at.as(DB::Any),
    }
  end

  # QueryBuilder overrides
  def self.table_name : String
    "outgoings"
  end

  def self.columns : Array(Symbol)
    [:id, :target_id, :line_protocol, :created_at]
  end

  private def self.column_types
    {Int64, Int64, String, String}
  end

  private def self.from_tuple(id : Int64?, tuple)
    Outgoing.new(
      target_id: tuple[1],
      line_protocol: tuple[2],
      created_at: tuple[3],
      id: tuple[0]
    )
  end
end
