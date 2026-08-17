# Parses a single InfluxDB line protocol line into measurement, tags, fields
# and timestamp.
#
# The separators `,`, `=` and space can appear inside a measurement, a tag or a
# field key. A writer escapes them with a backslash, so a parser that splits on
# the bare character cuts the line in the wrong place. A measurement named
# `PQ Inverter` arrives as `PQ\ Inverter` and must not become `PQ\`.
#
# Reference:
# https://docs.influxdata.com/influxdb/v2/reference/syntax/line-protocol/
class LineProtocolParser
  class InvalidLineProtocolError < StandardError; end

  TIMESTAMP_REGEX = /\A[-+]?\d+\z/

  # An integer carries an `i` suffix, an unsigned integer a `u` suffix. Only
  # the signed form takes a sign.
  INTEGER_REGEX = /\A(?:[-+]?\d+i|\d+u)\z/

  # A number without a suffix is a float. Line protocol allows a leading or
  # trailing dot and an exponent.
  FLOAT_REGEX = /\A[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?\z/

  # Line protocol spells a boolean in five ways per truth value.
  TRUE_VALUES = %w[t T true True TRUE].freeze
  FALSE_VALUES = %w[f F false False FALSE].freeze

  # Which escapes to resolve, per context. A writer escapes `,` and space in a
  # measurement, additionally `=` in any key, and `"` in a string value. A
  # backslash escapes itself everywhere, and a backslash before any other
  # character is literal (`\n` stays `\n`), so each context resolves only its
  # own set.
  MEASUREMENT_ESCAPE_REGEX = /\\([\\, ])/
  KEY_ESCAPE_REGEX = /\\([\\,= ])/
  VALUE_ESCAPE_REGEX = /\\([\\"])/

  # Reads the timestamp alone. The outbox groups queued lines by it and must
  # not pay for unescaping and value typing it never looks at. A line without a
  # timestamp, and a line that does not parse, both answer nil.
  def self.timestamp(line)
    new(line).timestamp
  rescue InvalidLineProtocolError
    nil
  end

  def initialize(line)
    @line = line.strip
  end

  def timestamp
    _name_and_tags, rest = split_head

    split_fields_and_time(rest).last
  end

  def parse
    invalid! if line.empty?

    name_and_tags, rest = split_head
    fields_str, time = split_fields_and_time(rest)
    name, *tag_parts = LineProtocolScanner.split(name_and_tags, ',')

    {
      name: unescape(name, MEASUREMENT_ESCAPE_REGEX),
      tags: parse_tags(tag_parts),
      fields: parse_fields(fields_str),
      time:,
    }
  end

  private

  attr_reader :line

  def invalid!
    raise InvalidLineProtocolError, "Invalid line protocol: #{line.presence || '(empty line)'}"
  end

  # Separates `<measurement>[,<tags>]` from the rest. Everything before the
  # first unescaped space is key-like, so no string value can begin there.
  def split_head
    LineProtocolScanner.split_once(line, ' ') || invalid!
  end

  def split_fields_and_time(rest)
    fields_str, time_str, extra = LineProtocolScanner.split(rest, ' ', field_set: true).reject(&:empty?)
    invalid! if fields_str.nil? || extra

    [fields_str, time_str && parse_time(time_str)]
  end

  def parse_time(str)
    invalid! unless str.match?(TIMESTAMP_REGEX)

    str.to_i
  end

  def parse_tags(tag_parts)
    tag_parts.to_h do |part|
      key, value = split_pair(part)
      [unescape(key, KEY_ESCAPE_REGEX), unescape(value.to_s, KEY_ESCAPE_REGEX)]
    end
  end

  def parse_fields(str)
    fields =
      LineProtocolScanner
        .split(str, ',', field_set: true)
        .to_h do |pair|
          key, value = split_pair(pair)
          invalid! if value.nil?

          # A field needs a key. `to_line_protocol` drops a field without one,
          # and a point that loses its last field serializes to nil.
          key = unescape(key, KEY_ESCAPE_REGEX)
          invalid! if key.empty?

          [key, parse_value(value)]
        end

    invalid! if fields.empty?

    fields
  end

  # Splits at the first unescaped `=`. Whatever follows is the value as a whole,
  # so a `=` inside a string value needs no special care.
  def split_pair(str)
    LineProtocolScanner.split_once(str, '=') || [str, nil]
  end

  # Every escape regex needs a backslash, and most lines carry none at all, so
  # the common case answers without allocating.
  def unescape(str, regex)
    return str unless str.include?(LineProtocolScanner::BACKSLASH)

    str.gsub(regex, '\1')
  end

  # Every documented value type is matched explicitly. An unknown value is
  # invalid, because a silent `to_f` turns garbage into a plausible `0.0`
  # reading that nothing downstream can tell apart from a real measurement.
  def parse_value(val)
    return unescape(val[1..-2], VALUE_ESCAPE_REGEX) if quoted?(val)
    return val[0..-2].to_i if val.match?(INTEGER_REGEX)
    return true if TRUE_VALUES.include?(val)
    return false if FALSE_VALUES.include?(val)

    invalid! unless val.match?(FLOAT_REGEX)

    float = val.to_f

    # An exponent can overflow to infinity. `to_line_protocol` drops such a
    # field, and a point that loses its last field serializes to nil.
    invalid! unless float.finite?

    float
  end

  def quoted?(val)
    val.length >= 2 && val.start_with?('"') && val.end_with?('"')
  end
end
