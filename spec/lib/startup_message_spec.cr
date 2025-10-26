require "../spec_helper"

describe StartupMessage do
  describe ".print!" do
    it "prints startup message to provided IO" do
      io = IO::Memory.new
      StartupMessage.print!(io)

      output = io.to_s
      output.should contain("Ingest for SOLECTRUS")
      output.should contain("Configured sensors:")
    end
  end
end
