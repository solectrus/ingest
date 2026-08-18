describe StartupMessage do
  describe '.print!' do
    it 'prints the startup message to stdout' do
      expect { described_class.print! }.to output(
        /Ingest for SOLECTRUS/,
      ).to_stdout
    end

    context 'when house_power is written to its own sensor' do
      before do
        allow(SensorEnvConfig).to receive(:house_power_calculated).and_return(
          { measurement: 'CALC', field: 'house_power' },
        )
      end

      it 'prints the destination of the calculation' do
        expect { described_class.print! }.to output(
          /Result of house_power calculation → CALC:house_power/,
        ).to_stdout
      end
    end

    context 'when house_power overrides the incoming value' do
      before do
        allow(SensorEnvConfig).to receive(:house_power_calculated).and_return(
          nil,
        )
      end

      it 'prints the override warning' do
        expect { described_class.print! }.to output(
          /will OVERRIDE the incoming value/,
        ).to_stdout
      end
    end
  end
end
