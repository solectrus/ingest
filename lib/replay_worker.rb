class ReplayWorker
  def initialize(batch_size: 1000)
    @batch_size = batch_size
  end

  attr_reader :batch_size

  # Triggers the replay of all unsynced data from the store
  def replay!
    loop do
      batch = fetch_batch
      break if batch.empty?

      lines = build_lines(batch)

      begin
        InfluxWriter.write(lines.join("\n"))
        mark_as_synced(batch)
      rescue StandardError => e
        puts "Replay failed: #{e.message}"
        break
      end
    end
  end

  private

  def fetch_batch
    STORE.db[:sensor_data]
      .where(synced: false)
      .order(:timestamp)
      .limit(batch_size)
      .all
  end

  def build_lines(batch)
    batch.map do |row|
      value = store.extract_value(row)

      LineProtocolParser.build(
        row[:measurement],
        row[:field],
        value,
        row[:timestamp],
      )
    end
  end

  def mark_as_synced(batch)
    batch.each do |row|
      store.db[:sensor_data].where(
        measurement: row[:measurement],
        field: row[:field],
        timestamp: row[:timestamp],
      ).update(synced: true)
    end
  end
end
