describe HousePowerCalculator do
  subject(:calculator) { described_class.new(target) }

  let(:target) do
    Target.create!(
      influx_token: 'test-token',
      bucket: 'test-bucket',
      org: 'test-org',
      precision: InfluxDB2::WritePrecision::NANOSECOND,
    )
  end

  let(:timestamp) { 1_000_000_000 }

  before do
    Incoming.create!(
      target:,
      timestamp:,
      measurement: 'SENEC',
      field: 'inverter_power',
      value: 500,
    )

    Incoming.create!(
      target:,
      timestamp:,
      measurement: 'SENEC',
      field: 'bat_power_plus',
      value: 200,
    )
  end

  describe '#recalculate' do
    subject(:recalculate) { calculator.recalculate(timestamp:) }

    it 'calculates house power and stores outgoing line' do
      expect { recalculate }.to change(Outgoing, :count).by(1)

      outgoing = Outgoing.last
      expect(outgoing.line_protocol).to eq(
        "SENEC house_power=300i #{timestamp}",
      )
    end
  end
end
