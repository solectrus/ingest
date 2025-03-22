require 'json'

class Buffer
  FILE = 'buffer.dump'
  REPLAY_FILE = 'buffer.replay'
  @mutex = Mutex.new

  class << self
    def add(entry)
      @mutex.synchronize do
        File.open(FILE, 'a') { |f| f.puts(entry.to_json) }
      end
    end

    def replay
      return unless File.exist?(FILE) || File.exist?(REPLAY_FILE)

      if File.exist?(REPLAY_FILE)
        lines = File.readlines(REPLAY_FILE)
      else
        @mutex.synchronize { File.rename(FILE, REPLAY_FILE) }
        lines = File.readlines(REPLAY_FILE)
      end

      success = true

      lines.each do |line|
        data = JSON.parse(line, symbolize_names: true)
        begin
          InfluxWriter.forward_influx_line(
            data[:influx_line],
            influx_token: data[:influx_token],
            bucket: data[:bucket],
            org: data[:org],
            precision: data[:precision]
          )
        rescue
          add(data)
          success = false
        end
      end

      File.delete(REPLAY_FILE) if success
    end
  end
end
