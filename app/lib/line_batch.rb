# Turns the lines of one write request into points.
#
# A line that does not parse is skipped, counted and logged. One malformed
# field of one collector must not stop the data of every other sensor in the
# same request.
#
# A batch with no valid line at all raises instead. The write route answers 400
# for that, so the client reads "nothing was stored" only when nothing was
# stored.
class LineBatch
  SKIPPED_STAT = :skipped_lines

  def initialize(lines)
    @lines = lines
  end

  def points
    @points ||= parse
  end

  private

  attr_reader :lines

  def parse
    error = nil

    result =
      lines.filter_map do |line|
        next if line.strip.empty?

        begin
          Point.parse(line)
        rescue LineProtocolParser::InvalidLineProtocolError => e
          error ||= e
          skip(e)
          nil
        end
      end

    raise error if result.empty? && error

    result
  end

  def skip(error)
    Stats.inc(SKIPPED_STAT)
    warn "[LineBatch] Skipped line: #{error.message}"
  end
end
