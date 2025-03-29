class InvalidLineProtocolError < StandardError
end

LINE_PROTOCOL_REGEX = /^([^ ]+)\s(.+?)(?:\s(\d+))?$/
INTEGER_REGEX = /\A[-+]?\d+i\z/
INTEGER_SUFFIX = 'i'.freeze
TRUE_STRING = 'true'.freeze
FALSE_STRING = 'false'.freeze
QUOTE = '"'.freeze

Line =
  Data.define(:measurement, :fields, :tags, :timestamp) do
    def self.parse(line)
      m = LINE_PROTOCOL_REGEX.match(line)
      raise InvalidLineProtocolError, "Invalid line protocol: #{line}" unless m

      measurement_and_tags = m[1]
      fields_str = m[2]
      timestamp = m[3]&.to_i

      measurement, *tag_parts = measurement_and_tags.split(',')
      tags = tag_parts.to_h { |t| t.split('=', 2) }
      fields = parse_fields(fields_str)

      new(measurement:, fields:, tags:, timestamp:)
    end

    class << self
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

      private :parse_fields, :parse_value
    end
  end
