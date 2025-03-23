class LineProtocolParser
  ParsedLine = Struct.new(:measurement, :tags, :fields, :timestamp)

  class << self
    # Parses a single InfluxDB line protocol string
    def parse(line)
      m = line.match(/^(\S+)\s(.+)\s(\d+)$/)
      return nil unless m

      measurement_and_tags = m[1]
      fields_str = m[2]
      timestamp = m[3].to_i

      measurement, *tag_parts = measurement_and_tags.split(',')
      tags = tag_parts.to_h { |t| t.split('=', 2) }

      fields = parse_fields(fields_str)
      ParsedLine.new(measurement, tags, fields, timestamp)
    end

    # Reconstructs a line protocol string from a ParsedLine object
    def build(parsed)
      tag_str = parsed.tags&.map { |k, v| "#{k}=#{v}" }&.join(',')
      tags_section = tag_str && !tag_str.empty? ? ",#{tag_str}" : ''

      fields_str = parsed.fields.map { |k, v| "#{k}=#{format_field_value(v)}" }.join(',')
      "#{parsed.measurement}#{tags_section} #{fields_str} #{parsed.timestamp}"
    end

    private

    def parse_fields(str)
      fields = {}
      str.split(',').each do |pair|
        key, value = pair.split('=', 2)
        fields[key] = parse_value(value)
      end
      fields
    end

    def parse_value(val)
      case val
      when /\A"(.*)"\z/ then Regexp.last_match(1)
      when /\A([-+]?\d+)i\z/ then Regexp.last_match(1).to_i
      when /\Atrue\z/ then true
      when /\Afalse\z/ then false
      else val.to_f
      end
    end

    def format_field_value(val)
      case val
      when String then "\"#{val}\""
      when TrueClass, FalseClass then val.to_s
      when Integer then "#{val}i"
      else val
      end
    end
  end
end
