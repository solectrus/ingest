# The stats page reports what leaves Ingest per minute. It counts values, not
# lines, because a collector that sends 26 fields in one line and a collector
# that sends 26 lines produce the same load and a very different line count.
#
# The number of fields is known when the line enters the queue, so the queue
# carries it. Counting it at delivery would parse every line again, on the
# path that InfluxDB waits for.
#
# A row that is already in the queue when this migration runs gets 1. Such a
# row leaves within seconds, so the number is too low for that time only.
class AddValuesCountToOutgoings < ActiveRecord::Migration[8.0]
  def change
    add_column :outgoings, :values_count, :integer, null: false, default: 1
  end
end
