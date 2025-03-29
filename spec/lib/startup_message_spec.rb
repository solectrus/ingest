describe StartupMessage do
  describe '.print!' do
    it 'prints the startup message to stdout' do
      expect { described_class.print! }.to output(
        /Ingest for SOLECTRUS/,
      ).to_stdout
    end
  end
end
