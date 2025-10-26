class Incoming < QueryBuilder::Base
  property id : Int64?
  property target_id : Int64
  property measurement : String
  property field : String
  property tags : String = "{}"
  property timestamp : Int64
  property value_int : Int64?
  property value_float : Float64?
  property value_bool : Bool?
  property value_string : String?
  property created_at : String

  def initialize(
    @target_id = 0_i64,
    @measurement = "",
    @field = "",
    @timestamp = 0_i64,
    @tags = "{}",
    @value_int = nil,
    @value_float = nil,
    @value_bool = nil,
    @value_string = nil,
    @created_at = Time.utc.to_s("%Y-%m-%d %H:%M:%S.%6N"),
    @id = nil,
  )
  end

  def value
    value_int || value_float || value_string || value_bool
  end

  def value=(val)
    @value_int = nil
    @value_float = nil
    @value_string = nil
    @value_bool = nil

    return if val.nil?

    case val
    when Int32, Int64
      @value_int = val.to_i64
    when Float64
      @value_float = val
    when Bool
      @value_bool = val
    when String
      @value_string = val
    else
      raise ArgumentError.new("Unsupported value type: #{val.class}")
    end
  end

  def tags_hash : Hash(String, String)
    JSON.parse(tags).as_h.transform_values(&.as_s)
  rescue
    {} of String => String
  end

  def tags_hash=(hash : Hash(String, String))
    @tags = hash.to_json
  end

  def attributes_for_save : Hash(Symbol, DB::Any)
    @created_at = Time.utc.to_s("%Y-%m-%d %H:%M:%S.%6N") unless @id

    bool_value = @value_bool.nil? ? nil : (@value_bool ? 1 : 0)

    Hash(Symbol, DB::Any){
      :target_id    => @target_id.as(DB::Any),
      :measurement  => @measurement.as(DB::Any),
      :field        => @field.as(DB::Any),
      :tags         => @tags.as(DB::Any),
      :timestamp    => @timestamp.as(DB::Any),
      :value_int    => @value_int.as(DB::Any),
      :value_float  => @value_float.as(DB::Any),
      :value_bool   => bool_value.as(DB::Any),
      :value_string => @value_string.as(DB::Any),
      :created_at   => @created_at.as(DB::Any),
    }
  end

  def save! : Incoming
    # Call parent save!
    super

    # Cache sensor value
    if (v = value_int || value_float)
      SensorValueCache.instance.write(
        measurement: measurement,
        field: field,
        timestamp: timestamp,
        value: v.to_f64
      )
    end

    self
  end

  # QueryBuilder overrides
  def self.table_name : String
    "incomings"
  end

  def self.columns : Array(Symbol)
    [:id, :target_id, :measurement, :field, :tags, :timestamp, :value_int, :value_float, :value_bool, :value_string, :created_at]
  end

  private def self.column_types
    {Int64, Int64, String, String, String, Int64, Int64?, Float64?, Int32?, String?, String}
  end

  private def self.from_tuple(id : Int64?, tuple)
    incoming = Incoming.new(
      target_id: tuple[1],
      measurement: tuple[2],
      field: tuple[3],
      timestamp: tuple[5],
      tags: tuple[4],
      value_int: tuple[6],
      value_float: tuple[7],
      created_at: tuple[10],
      id: tuple[0]
    )
    incoming.value_bool = tuple[8] == 1 if tuple[8]
    incoming.value_string = tuple[9]
    incoming
  end
end
