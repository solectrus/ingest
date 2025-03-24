class InvalidLineProtocolError < StandardError
end

class Line
  attr_reader :measurement, :tags, :fields, :timestamp

  def initialize(measurement:, fields:, timestamp:, tags: {})
    @measurement = measurement
    @fields = fields
    @tags = tags
    @timestamp = timestamp
  end

  def self.parse(line)
    m = line.match(/^([^ ]+)\s(.+)\s(\d+)$/)
    raise InvalidLineProtocolError, "Invalid line protocol: #{line}" unless m

    measurement_and_tags = m[1]
    fields_str = m[2]
    timestamp = m[3].to_i

    measurement, *tag_parts = measurement_and_tags.split(',')
    tags = tag_parts.to_h { |t| t.split('=', 2) }
    fields = parse_fields(fields_str)

    new(
      measurement: measurement,
      fields: fields,
      tags: tags,
      timestamp: timestamp,
    )
  end

  def to_s
    tag_str = tags.map { |k, v| "#{k}=#{v}" }.join(',')
    tag_section = tag_str.empty? ? '' : ",#{tag_str}"

    field_str = fields.map { |k, v| "#{k}=#{format_field_value(v)}" }.join(',')

    "#{measurement}#{tag_section} #{field_str} #{timestamp}"
  end

  private

  def self.parse_fields(str)
    str
      .split(',')
      .to_h do |pair|
        key, value = pair.split('=', 2)
        [key, parse_value(value)]
      end
  end

  def self.parse_value(val)
    case val
    when /^"(.*)"$/
      Regexp.last_match(1)
    when /^([-+]?\d+)i$/
      Regexp.last_match(1).to_i
    when 'true'
      true
    when 'false'
      false
    else
      val.to_f
    end
  end

  def format_field_value(val)
    case val
    when String
      "\"#{val}\""
    when TrueClass, FalseClass
      val.to_s
    when Integer
      "#{val}i"
    else
      val
    end
  end
end
