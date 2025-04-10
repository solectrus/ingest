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
    # Create Incoming for all relevant fields
    {
      %w[SENEC inverter_power] => 500,
      %w[SENEC bat_power_plus] => 200,
      %w[SENEC bat_power_minus] => 0,
      %w[SENEC grid_power_plus] => 0,
      %w[SENEC grid_power_minus] => 0,
      %w[SENEC wallbox_charge_power] => 0,
      %w[SENEC house_power] => 9999,
      %w[balcony inverter_power] => 0,
      %w[Heatpump power] => 0,
    }.each do |(measurement, field), value|
      Incoming.create!(
        target:,
        timestamp:,
        measurement:,
        field:,
        value:,
      )
    end
  end

  after do
    SensorValueCache.instance.reset!
    described_class.reset_stats
  end

  describe '#recalculate' do
    it 'calculates house power and stores outgoing line' do
      expect { calculator.recalculate(timestamp:) }.to change(Outgoing, :count).by(1)

      outgoing = Outgoing.last
      expect(outgoing.line_protocol).to eq(
        "SENEC house_power=300i #{timestamp}",
      )
    end

    it 'tracks recalculate' do
      expect(described_class.count_recalculate).to eq(0)
      calculator.recalculate(timestamp:)
      expect(described_class.count_recalculate).to eq(1)
    end

    it 'tracks cache hit' do
      calculator.recalculate(timestamp:)
      expect(described_class.cache_hits).to eq(1)
    end

    it 'tracks cache miss when requesting timestamp older than cache' do
      calculator.recalculate(timestamp: timestamp - 1)
      expect(described_class.cache_hits).to eq(0)
    end

    it 'tracks cache miss when one field is not in cache' do
      SensorValueCache.instance.delete(measurement: 'SENEC', field: 'grid_power_minus')
      calculator.recalculate(timestamp: timestamp)
      expect(described_class.cache_hits).to eq(0)
    end
  end
end
