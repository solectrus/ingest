describe Store do
  let(:store) { STORE }

  let(:target) do
    Target.create!(
      influx_token: 'test-token',
      bucket: 'test-bucket',
      org: 'test-org',
    )
  end

  it 'saves integer values correctly' do
    store.save_sensor(
      target:,
      measurement: 'SENEC',
      field: 'inverter_power',
      timestamp: 1000,
      value: 42,
    )
    row = Sensor.first
    expect(row.value_int).to eq(42)
  end

  it 'saves float values correctly' do
    store.save_sensor(
      target:,
      measurement: 'SENEC',
      field: 'inverter_power',
      timestamp: 1000,
      value: 42.5,
    )
    row = Sensor.first
    expect(row.value_float).to eq(42.5)
  end

  it 'interpolates between two points' do # rubocop:disable RSpec/ExampleLength
    store.save_sensor(
      target:,
      measurement: 'SENEC',
      field: 'inverter_power',
      timestamp: 1000,
      value: 100,
    )
    store.save_sensor(
      target:,
      measurement: 'SENEC',
      field: 'inverter_power',
      timestamp: 2000,
      value: 200,
    )

    expect(
      store.interpolate(
        measurement: 'SENEC',
        field: 'inverter_power',
        timestamp: 1500,
      ),
    ).to eq(150.0)
  end

  it 'returns exact value if timestamp matches' do
    store.save_sensor(
      target:,
      measurement: 'SENEC',
      field: 'inverter_power',
      timestamp: 1000,
      value: 100,
    )
    expect(
      store.interpolate(
        measurement: 'SENEC',
        field: 'inverter_power',
        timestamp: 1000,
      ),
    ).to eq(100)
  end

  it 'cleans up old data' do
    store.save_sensor(
      target:,
      measurement: 'SENEC',
      field: 'inverter_power',
      timestamp: 1000,
      value: 100,
    )
    store.save_sensor(
      target:,
      measurement: 'SENEC',
      field: 'inverter_power',
      timestamp: 2000,
      value: 200,
    )
    store.cleanup(1500)

    expect(Sensor.count).to eq(1)
    expect(Sensor.first.timestamp).to eq(2000)
  end
end
