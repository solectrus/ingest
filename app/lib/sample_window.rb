# Holds every sample that one window of timestamps needs, and finds the two
# samples that surround a timestamp inside it.
#
# The interpolator asked the database once per timestamp before. A backfill
# carries one timestamp per collector poll, so a request of 5000 points made
# 5000 queries. The timestamps of one window now share a single query, and the
# bounds come from a binary search over the result.
class SampleWindow
  Sample = Struct.new(:id, :timestamp, :value)

  def self.load(pairs:, first:, last:)
    new(pairs:, first:, last:)
  end

  def initialize(pairs:, first:, last:)
    @samples = read(pairs, first, last)
  end

  # The nearest sample at or before the timestamp, and the nearest one at or
  # after it. Both are nil when the pair has no sample at all.
  def bounds(pair, timestamp)
    samples = @samples[pair] || []

    index = samples.bsearch_index { |sample| sample.timestamp >= timestamp }
    return [samples.last, nil] if index.nil?

    nxt = samples[index]
    return [nxt, nxt] if nxt.timestamp == timestamp

    [(samples[index - 1] if index.positive?), nxt]
  end

  private

  def read(pairs, first, last)
    rows = ActiveRecord::Base.connection.exec_query(query(pairs, first, last))

    grouped =
      rows.each_with_object({}) do |row, result|
        key = [row['measurement'], row['field']]
        (result[key] ||= []) << Sample.new(
          row['id'],
          row['timestamp'],
          row['value'],
        )
      end

    grouped.transform_values { |samples| newest_per_timestamp(samples) }
  end

  # Two rows can carry the same measurement, field and timestamp. A collector
  # that runs into a timeout sends its batch again, and the second write lands
  # next to the first one. The row written last holds the newest reading, so
  # it wins and the answer does not depend on the order the database returns.
  def newest_per_timestamp(samples)
    samples
      .sort_by { |sample| [sample.timestamp, sample.id] }
      .chunk_while { |a, b| a.timestamp == b.timestamp }
      .map(&:last)
  end

  # Three index seeks per pair: the samples inside the window, plus the
  # nearest one on each side. The index on (measurement, field, timestamp)
  # answers each branch, so the cost does not grow with the size of the table.
  def query(pairs, first, last)
    connection = ActiveRecord::Base.connection
    from = connection.quote(first)
    to = connection.quote(last)

    pairs
      .flat_map do |measurement, field|
        m = connection.quote(measurement)
        f = connection.quote(field)

        [
          branch(m, f, "timestamp BETWEEN #{from} AND #{to}"),
          branch(m, f, "timestamp < #{from}", order: 'DESC', limit: true),
          branch(m, f, "timestamp > #{to}", order: 'ASC', limit: true),
        ]
      end
      .join(' UNION ALL ')
  end

  # SQLite rejects ORDER BY inside a compound branch, so each branch is
  # wrapped in a subquery.
  def branch(measurement, field, condition, order: nil, limit: false)
    <<~SQL.squish
      SELECT * FROM (
        SELECT #{measurement} AS measurement,
               #{field} AS field,
               id,
               timestamp,
               COALESCE(value_int, value_float) AS value
        FROM incomings
        WHERE measurement = #{measurement}
          AND field = #{field}
          AND #{condition}
        #{"ORDER BY timestamp #{order}, id DESC" if order}
        #{'LIMIT 1' if limit}
      )
    SQL
  end
end
