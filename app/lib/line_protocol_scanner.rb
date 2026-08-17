# Cuts a line protocol line at separators that actually separate.
#
# Reference:
# https://docs.influxdata.com/influxdb/v2/reference/syntax/line-protocol/
#
# Two of its rules apply here:
#
#   - A backslash escapes the character after it. `\\` is a single backslash, a
#     backslash before anything else stays literal (`C:\path`).
#   - A double quote only opens a string field value, which is the one place a
#     separator can appear unescaped. Everywhere else (measurement, tag key,
#     tag value, field key) a quote is an ordinary character. A string value
#     starts right after the `=` of its field, so a quote anywhere else opens
#     nothing.
#
# So the scanner knows the escape rule and the string-value rule. Which region
# of the line it is cutting is the caller's knowledge, passed in as `field_set`.
class LineProtocolScanner
  # `bare?` compares against these once per character, and a string literal
  # allocates on every evaluation, so they stay named and frozen.
  QUOTE = '"'.freeze
  BACKSLASH = '\\'.freeze
  EQUALS = '='.freeze

  class State
    def initialize(field_set:)
      @field_set = field_set
      @escaped = false
      @in_value = false
      @value_may_start = false
    end

    def separates?(char)
      separates = bare?(char)
      @value_may_start = separates && @field_set && char == EQUALS
      separates
    end

    private

    # True when the character stands bare: neither escaped, nor the escape
    # itself, nor part of a string value.
    def bare?(char)
      if @escaped
        @escaped = false
      elsif char == BACKSLASH
        @escaped = true
      elsif @in_value
        @in_value = false if char == QUOTE
      elsif @value_may_start && char == QUOTE
        @in_value = true
      else
        return true
      end

      false
    end
  end

  # `separates?` answers correctly only when called on every character in
  # order, so the state machine stays inside this class.
  private_constant :State, :QUOTE, :EQUALS

  class << self
    # Enable `field_set` for the field set, where a quote after `=` opens a
    # string value. Leave it off for the measurement and tags, where a quote is
    # an ordinary character.
    def split(str, delimiter, field_set: false)
      state = State.new(field_set:)
      parts = []
      current = +''

      str.each_char do |char|
        if state.separates?(char) && char == delimiter
          parts << current
          current = +''
        else
          current << char
        end
      end

      parts << current
    end

    # Cuts at the first separating delimiter and returns `[head, rest]`, or nil
    # if the delimiter does not occur. Only ever used on key-like input, so it
    # needs no string-value tracking.
    def split_once(str, delimiter)
      state = State.new(field_set: false)

      str.each_char.with_index do |char, index|
        return [str[0...index], str[(index + 1)..]] if state.separates?(char) && char == delimiter
      end

      nil
    end
  end
end
