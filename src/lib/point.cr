class Point
  LINE_PROTOCOL_REGEX = /^([^ ]+)\s(.+?)(?:\s(\d+))?$/
  INTEGER_REGEX       = /\A[-+]?\d+i\z/
  INTEGER_SUFFIX      = "i"
  TRUE_STRING         = "true"
  FALSE_STRING        = "false"
  QUOTE               = "\""

  alias FieldValue = Int64 | Float64 | String | Bool

  property name : String
  property fields : Hash(String, FieldValue)
  property tags : Hash(String, String)
  property time : Int64?

  def initialize(
    @name : String,
    @fields : Hash(String, FieldValue),
    @tags : Hash(String, String) = {} of String => String,
    @time : Int64? = nil,
  )
  end

  def self.parse(line : String) : Point
    m = LINE_PROTOCOL_REGEX.match(line)
    raise InvalidLineProtocolError.new("Invalid line protocol: #{line}") unless m

    name_and_tags = m[1]
    fields_str = m[2]
    time = m[3]?.try(&.to_i64)

    parts = name_and_tags.split(',')
    name = parts[0]
    tag_parts = parts[1..]

    tags = tag_parts.to_h do |t|
      key, value = t.split('=', 2)
      {key, value}
    end

    fields = parse_fields(fields_str)

    new(name: name, fields: fields, tags: tags, time: time)
  end

  private def self.parse_fields(str : String) : Hash(String, Int64 | Float64 | String | Bool)
    result = {} of String => (Int64 | Float64 | String | Bool)
    str.split(',').each do |pair|
      key, value = pair.split('=', 2)
      result[key] = parse_value(value)
    end
    result
  end

  private def self.parse_value(val : String) : Int64 | Float64 | String | Bool
    if val.starts_with?(QUOTE) && val.ends_with?(QUOTE)
      val[1..-2]
    elsif val.ends_with?(INTEGER_SUFFIX) && val.matches?(INTEGER_REGEX)
      val[0..-2].to_i64
    elsif val == TRUE_STRING
      true
    elsif val == FALSE_STRING
      false
    else
      val.to_f64
    end
  end

  def to_line_protocol : String
    # Measurement and tags
    result = name
    unless tags.empty?
      tags.each do |k, v|
        result += ",#{k}=#{v}"
      end
    end

    # Fields
    result += " "
    field_strings = fields.map do |k, v|
      value_str = case v
                  when Int64
                    "#{v}i"
                  when Float64
                    v.to_s
                  when String
                    "\"#{v}\""
                  when Bool
                    v.to_s
                  else
                    v.to_s
                  end
      "#{k}=#{value_str}"
    end
    result += field_strings.join(",")

    # Timestamp
    if (t = time)
      result += " #{t}"
    end

    result
  end
end
