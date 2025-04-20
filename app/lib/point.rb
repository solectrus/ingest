class InvalidLineProtocolError < StandardError
end

class Point < InfluxDB2::Point
  LINE_PROTOCOL_REGEX = /^([^ ]+)\s(.+?)(?:\s(\d+))?$/
  INTEGER_REGEX = /\A[-+]?\d+i\z/
  INTEGER_SUFFIX = 'i'.freeze
  TRUE_STRING = 'true'.freeze
  FALSE_STRING = 'false'.freeze
  QUOTE = '"'.freeze

  attr_reader :name, :fields, :tags, :time

  def self.parse(line)
    m = LINE_PROTOCOL_REGEX.match(line)
    raise InvalidLineProtocolError, "Invalid line protocol: #{line}" unless m

    name_and_tags = m[1]
    fields_str = m[2]
    time = m[3]&.to_i

    name, *tag_parts = name_and_tags.split(',')
    tags = tag_parts.to_h { |t| t.split('=', 2) }
    fields = parse_fields(fields_str)

    new(name:, fields:, tags:, time:)
  end

  class << self
    private

    def parse_fields(str)
      str
        .split(',')
        .to_h do |pair|
          key, value = pair.split('=', 2)
          [key, parse_value(value)]
        end
    end

    def parse_value(val)
      if val.start_with?(QUOTE) && val.end_with?(QUOTE)
        val[1..-2]
      elsif val.end_with?(INTEGER_SUFFIX) && val.match?(INTEGER_REGEX)
        val[0..-2].to_i
      elsif val == TRUE_STRING
        true
      elsif val == FALSE_STRING
        false
      else
        val.to_f
      end
    end
  end
end
