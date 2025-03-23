describe Store do
  let(:store) { described_class.new(DB_TEST) }

  it 'saves integer values correctly' do
    store.save(measurement: 'SENEC', field: 'power', timestamp: 1000, value: 42)
    row = DB_TEST[:sensor_data].first
    expect(row[:value_int]).to eq(42)
  end

  it 'saves float values correctly' do
    store.save(
      measurement: 'SENEC',
      field: 'power',
      timestamp: 1000,
      value: 42.5,
    )
    row = DB_TEST[:sensor_data].first
    expect(row[:value_float]).to eq(42.5)
  end

  it 'interpolates between two points' do
    store.save(
      measurement: 'SENEC',
      field: 'power',
      timestamp: 1000,
      value: 100,
    )
    store.save(
      measurement: 'SENEC',
      field: 'power',
      timestamp: 2000,
      value: 200,
    )
    expect(
      store.interpolate(measurement: 'SENEC', field: 'power', target_ts: 1500),
    ).to eq(150.0)
  end

  it 'returns exact value if timestamp matches' do
    store.save(
      measurement: 'SENEC',
      field: 'power',
      timestamp: 1000,
      value: 100,
    )
    expect(
      store.interpolate(measurement: 'SENEC', field: 'power', target_ts: 1000),
    ).to eq(100)
  end

  it 'cleans up old data' do
    store.save(
      measurement: 'SENEC',
      field: 'power',
      timestamp: 1000,
      value: 100,
    )
    store.save(
      measurement: 'SENEC',
      field: 'power',
      timestamp: 2000,
      value: 200,
    )
    store.cleanup(1500)
    expect(DB_TEST[:sensor_data].count).to eq(1)
    expect(DB_TEST[:sensor_data].first[:timestamp]).to eq(2000)
  end
end
