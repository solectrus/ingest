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
    m = line.match(/^([^ ]+)\s(.+?)(?:\s(\d+))?$/)
    raise InvalidLineProtocolError, "Invalid line protocol: #{line}" unless m

    measurement_and_tags = m[1]
    fields_str = m[2]
    timestamp = m[3]&.to_i

    measurement, *tag_parts = measurement_and_tags.split(',')
    tags = tag_parts.to_h { |t| t.split('=', 2) }
    fields = parse_fields(fields_str)

    new(measurement:, fields:, tags:, timestamp:)
  end

  def to_s
    tag_str = tags.map { |k, v| "#{k}=#{v}" }.join(',')
    tag_section = tag_str.empty? ? '' : ",#{tag_str}"

    field_str = fields.map { |k, v| "#{k}=#{format_field_value(v)}" }.join(',')

    ["#{measurement}#{tag_section} #{field_str}", timestamp].compact.join(' ')
  end

  private

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

  class << self
    def parse_fields(str)
      str
        .split(',')
        .to_h do |pair|
          key, value = pair.split('=', 2)
          [key.to_sym, parse_value(value)]
        end
    end

    def parse_value(val)
      case val
      when /^"(.*)"$/ # string
        Regexp.last_match(1)
      when /^([-+]?\d+)i$/ # integer
        Regexp.last_match(1).to_i
      when 'true' # boolean
        true
      when 'false' # boolean
        false
      else # float
        val.to_f
      end
    end

    private :parse_fields, :parse_value
  end
end
