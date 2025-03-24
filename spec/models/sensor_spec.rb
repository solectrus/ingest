describe Sensor do
  let(:target) do
    Target.create!(
      influx_token: 'test-token',
      bucket: 'test-bucket',
      org: 'test-org',
    )
  end

  it 'saves integer values correctly' do
    target.sensors.create!(
      measurement: 'SENEC',
      field: 'inverter_power',
      timestamp: 1000,
      value: 42,
    )
    row = described_class.first
    expect(row.value_int).to eq(42)
  end

  it 'saves float values correctly' do
    target.sensors.create!(
      measurement: 'SENEC',
      field: 'inverter_power',
      timestamp: 1000,
      value: 42.5,
    )
    row = described_class.first
    expect(row.value_float).to eq(42.5)
  end

  it 'interpolates between two points' do
    target.sensors.create!(
      measurement: 'SENEC',
      field: 'inverter_power',
      timestamp: 1000,
      value: 100,
    )
    target.sensors.create!(
      measurement: 'SENEC',
      field: 'inverter_power',
      timestamp: 2000,
      value: 200,
    )

    expect(
      described_class.interpolate(
        measurement: 'SENEC',
        field: 'inverter_power',
        timestamp: 1500,
      ),
    ).to eq(150.0)
  end

  it 'returns exact value if timestamp matches' do
    target.sensors.create!(
      measurement: 'SENEC',
      field: 'inverter_power',
      timestamp: 1000,
      value: 100,
    )
    expect(
      described_class.interpolate(
        measurement: 'SENEC',
        field: 'inverter_power',
        timestamp: 1000,
      ),
    ).to eq(100)
  end

  it 'cleans up old data' do
    target.sensors.create!(
      measurement: 'SENEC',
      field: 'inverter_power',
      timestamp: 1000,
      value: 100,
    )
    target.sensors.create!(
      measurement: 'SENEC',
      field: 'inverter_power',
      timestamp: 2000,
      value: 200,
    )
    described_class.cleanup(1500)

    expect(described_class.count).to eq(1)
    expect(described_class.first.timestamp).to eq(2000)
  end
end
