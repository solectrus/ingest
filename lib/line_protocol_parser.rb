class LineProtocolParser
  ParsedLine = Struct.new(:measurement, :tags, :fields, :timestamp)

  class << self
    # Parses a single InfluxDB line protocol string
    def parse(line)
      match = line.match(/^(\S+)\s(.+)\s(\d+)$/)
      return nil unless match

      measurement, *tag_parts = match[1].split(',')
      fields = parse_fields(match[2])
      tags = tag_parts.to_h { |t| t.split('=', 2) }
      timestamp = match[3].to_i

      ParsedLine.new(measurement, tags, fields, timestamp)
    end

    # Reconstructs a line protocol string from a ParsedLine object
    def build(parsed)
      tag_str = parsed.tags&.map { |k, v| "#{k}=#{v}" }&.join(',')
      tags_section = tag_str && !tag_str.empty? ? ",#{tag_str}" : ''

      fields_str =
        parsed.fields.map { |k, v| "#{k}=#{format_field_value(v)}" }.join(',')
      "#{parsed.measurement}#{tags_section} #{fields_str} #{parsed.timestamp}"
    end

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
      case val
      when /\A"(.*)"\z/
        Regexp.last_match(1)
      when /\A([-+]?\d+)i\z/
        Regexp.last_match(1).to_i
      when /\Atrue\z/
        true
      when /\Afalse\z/
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
end
