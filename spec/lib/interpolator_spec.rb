describe Interpolator do
  let(:timestamp) { 1_000 }

  let(:target) do
    Target.create!(
      influx_token: 'foo',
      bucket: 'test',
      org: 'test',
      precision: InfluxDB2::WritePrecision::NANOSECOND,
    )
  end

  before do
    target.incomings.create!(
      measurement: 'SENEC',
      field: 'inverter_power',
      timestamp: 990,
      value: 1000,
    )
    target.incomings.create!(
      measurement: 'SENEC',
      field: 'inverter_power',
      timestamp: 1010,
      value: 1200,
    )

    target.incomings.create!(
      measurement: 'SENEC',
      field: 'wallbox_charge_power',
      timestamp: 980,
      value: 0,
    )
  end

  it 'returns interpolated values from real ENV sensor config' do
    result =
      described_class.new(
        sensor_keys: %i[inverter_power wallbox_power],
        timestamp:,
      ).run

    expect(result[:inverter_power]).to eq(1100.0)
    expect(result[:wallbox_power]).to eq(0.0)
  end

  it 'returns nothing if all sensors are missing' do
    result =
      described_class.new(
        sensor_keys: %i[balcony_inverter_power grid_import_power],
        timestamp:,
      ).run
    expect(result).to be_empty
  end

  it 'ignores sensors not set in ENV' do
    ENV['INFLUX_SENSOR_GRID_IMPORT_POWER'] = '' # bewusst leer
    result =
      described_class.new(
        sensor_keys: %i[inverter_power grid_import_power],
        timestamp:,
      ).run
    expect(result.keys).to eq([:inverter_power])
  end
end
