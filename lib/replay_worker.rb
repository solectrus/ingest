class ReplayWorker
  def initialize(batch_size: 1000)
    @batch_size = batch_size
  end

  attr_reader :batch_size

  def replay!
    Target.find_each do |target|
      loop do
        batch = fetch_batch(target)
        break if batch.empty?

        lines = build_lines(batch)

        begin
          InfluxWriter.write(
            lines.join("\n"),
            influx_token: target.influx_token,
            bucket: target.bucket,
            org: target.org,
            precision: target.precision,
          )

          batch.each(&:mark_synced!)
        rescue StandardError => e
          puts "Replay failed for target #{target.id}: #{e.message}"
          break
        end
      end
    end
  end

  private

  def fetch_batch(target)
    target.sensors.where(synced: false).order(:timestamp).limit(batch_size)
  end

  def build_lines(batch)
    batch.map do |sensor|
      Line.new(
        measurement: sensor.measurement,
        fields: {
          sensor.field => sensor.extracted_value,
        },
        timestamp: sensor.timestamp,
      ).to_s
    end
  end
end
