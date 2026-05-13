describe Interpolator do
  let(:timestamp) { 1_000 }
  let(:max_age) { 1_000 }

  let(:target) do
    Target.create!(
      influx_token: 'foo',
      bucket: 'test',
      org: 'test',
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
        max_age:,
      ).run

    expect(result[:inverter_power]).to eq(1100.0)
    expect(result[:wallbox_power]).to eq(0.0)
  end

  it 'returns nothing if all sensors are missing' do
    result =
      described_class.new(
        sensor_keys: %i[inverter_power_1 grid_import_power],
        timestamp:,
        max_age:,
      ).run
    expect(result).to be_empty
  end

  it 'ignores sensors not set in ENV' do
    stub_const(
      'ENV',
      ENV.to_hash.merge('INFLUX_SENSOR_GRID_IMPORT_POWER' => ''),
    )

    result =
      described_class.new(
        sensor_keys: %i[inverter_power grid_import_power],
        timestamp:,
        max_age:,
      ).run
    expect(result.keys).to eq([:inverter_power])
  end

  it 'omits sensors whose only prev sample is older than max_age' do
    # wallbox_charge_power has a single prev sample at timestamp 980,
    # 20 units older than the target timestamp.
    result =
      described_class.new(
        sensor_keys: %i[inverter_power wallbox_power],
        timestamp:,
        max_age: 10,
      ).run

    expect(result.keys).to eq([:inverter_power])
  end

  it 'still interpolates between two samples regardless of max_age' do
    # inverter_power has prev (990) and next (1010) — interpolation is
    # always valid for surrounding samples.
    result =
      described_class.new(
        sensor_keys: %i[inverter_power],
        timestamp:,
        max_age: 1,
      ).run

    expect(result[:inverter_power]).to eq(1100.0)
  end
end
