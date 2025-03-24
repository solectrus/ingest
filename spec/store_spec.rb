describe Store do
  let(:store) { STORE }

  let(:target_id) do
    store.save_target(
      influx_token: 'test-token',
      bucket: 'test-bucket',
      org: 'test-org',
    )
  end

  it 'saves integer values correctly' do
    store.save(
      measurement: 'SENEC',
      field: 'inverter_power',
      timestamp: 1000,
      value: 42,
      target_id:,
    )
    row = STORE.db[:sensor_data].first
    expect(row[:value_int]).to eq(42)
  end

  it 'saves float values correctly' do
    store.save(
      measurement: 'SENEC',
      field: 'inverter_power',
      timestamp: 1000,
      value: 42.5,
      target_id:,
    )
    row = STORE.db[:sensor_data].first
    expect(row[:value_float]).to eq(42.5)
  end

  it 'interpolates between two points' do # rubocop:disable RSpec/ExampleLength
    store.save(
      measurement: 'SENEC',
      field: 'inverter_power',
      timestamp: 1000,
      value: 100,
      target_id:,
    )
    store.save(
      measurement: 'SENEC',
      field: 'inverter_power',
      timestamp: 2000,
      value: 200,
      target_id:,
    )

    expect(
      store.interpolate(
        measurement: 'SENEC',
        field: 'inverter_power',
        target_ts: 1500,
      ),
    ).to eq(150.0)
  end

  it 'returns exact value if timestamp matches' do
    store.save(
      measurement: 'SENEC',
      field: 'inverter_power',
      timestamp: 1000,
      value: 100,
      target_id:,
    )
    expect(
      store.interpolate(
        measurement: 'SENEC',
        field: 'inverter_power',
        target_ts: 1000,
      ),
    ).to eq(100)
  end

  it 'cleans up old data' do
    store.save(
      measurement: 'SENEC',
      field: 'inverter_power',
      timestamp: 1000,
      value: 100,
      target_id:,
    )
    store.save(
      measurement: 'SENEC',
      field: 'inverter_power',
      timestamp: 2000,
      value: 200,
      target_id:,
    )
    store.cleanup(1500)

    expect(STORE.db[:sensor_data].count).to eq(1)
    expect(STORE.db[:sensor_data].first[:timestamp]).to eq(2000)
  end
end
