class LineProtocolParser
  ParsedLine = Struct.new(:measurement, :tags, :fields, :timestamp)

  class << self
    # Parses a single InfluxDB line protocol string
    def parse(line)
      return unless line =~ /^(\w+),?([^ ]*) ([^ ]+) (\d+)$/

      measurement = Regexp.last_match(1)
      tags = Regexp.last_match(2)
      fields_str = Regexp.last_match(3)
      timestamp = Regexp.last_match(4).to_i

      fields = fields_str.split(',').to_h do |f|
        key, value = f.split('=')
        [key, value.to_f]
      end

      ParsedLine.new(measurement, tags, fields, timestamp)
    end

    # Reconstructs a line protocol string from a ParsedLine object
    def build(parsed_line)
      field_str = parsed_line.fields.map { |k, v| "#{k}=#{v}" }.join(',')
      if parsed_line.tags && !parsed_line.tags.empty?
        "#{parsed_line.measurement},#{parsed_line.tags} #{field_str} #{parsed_line.timestamp}"
      else
        "#{parsed_line.measurement} #{field_str} #{parsed_line.timestamp}"
      end
    end
  end
end
