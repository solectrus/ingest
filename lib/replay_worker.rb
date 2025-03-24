class ReplayWorker
  def initialize(batch_size: 1000)
    @batch_size = batch_size
  end

  attr_reader :batch_size

  def replay!
    STORE.db[:targets].each do |target|
      loop do
        batch = fetch_batch(target[:id])
        break if batch.empty?

        lines = build_lines(batch)

        begin
          InfluxWriter.write(
            lines.join("\n"),
            influx_token: target[:influx_token],
            bucket: target[:bucket],
            org: target[:org],
            precision: target[:precision],
          )
          mark_as_synced(batch)
        rescue StandardError => e
          puts "Replay failed for target #{target[:id]}: #{e.message}"
          break
        end
      end
    end
  end

  private

  def fetch_batch(target_id)
    STORE.db[:sensor_data]
      .where(synced: false, target_id:)
      .order(:timestamp)
      .limit(batch_size)
      .all
  end

  def build_lines(batch)
    batch.map do |row|
      value = STORE.extract_value(row)
      Line.new(
        measurement: row[:measurement],
        fields: {
          row[:field] => value,
        },
        timestamp: row[:timestamp],
      ).to_s
    end
  end

  def mark_as_synced(batch)
    batch.each do |row|
      STORE.mark_synced(
        measurement: row[:measurement],
        field: row[:field],
        timestamp: row[:timestamp],
        target_id: row[:target_id],
      )
    end
  end
end
