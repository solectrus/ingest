class Point < InfluxDB2::Point
  # The parent exposes none of these as readers. `time` is the exception: there
  # it is a two-argument fluent setter, so the reader is named `timestamp` to
  # leave the inherited method intact.
  attr_reader :name, :fields, :tags

  def self.parse(line)
    new(**LineProtocolParser.new(line).parse)
  end

  def timestamp
    @time
  end
end
