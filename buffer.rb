require 'json'

class Buffer
  FILE = 'tmp/buffer.dump'.freeze
  REPLAY_FILE = 'tmp/buffer.replay'.freeze
  @mutex = Mutex.new

  class << self
    def add(entry)
      @mutex.synchronize do
        File.open(FILE, 'a') { |f| f.puts(entry.to_json) }
      end
    end

    def replay
      return unless prepare_replay

      success = process_replay_file

      File.delete(REPLAY_FILE) if success
    end

    private

    def prepare_replay
      return false unless File.exist?(FILE) || File.exist?(REPLAY_FILE)

      @mutex.synchronize do
        File.rename(FILE, REPLAY_FILE) if File.exist?(FILE) && !File.exist?(REPLAY_FILE)
      end

      File.exist?(REPLAY_FILE)
    end

    def process_replay_file
      File.foreach(REPLAY_FILE).all? do |line|
        process_line(line)
      end
    end

    def process_line(line)
      data = JSON.parse(line, symbolize_names: true)

      InfluxWriter.forward_influx_line(
        data[:influx_line],
        influx_token: data[:influx_token],
        bucket: data[:bucket],
        org: data[:org],
        precision: data[:precision],
      )
      true
    rescue SocketError, Timeout::Error, Errno::ECONNREFUSED
      add(data)
      false
    end
  end
end
