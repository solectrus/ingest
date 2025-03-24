describe LineProcessor do
  subject(:processor) do
    described_class.new(influx_token, bucket, org, precision)
  end

  let(:influx_token) { 'test-token' }
  let(:bucket) { 'test-bucket' }
  let(:org) { 'test-org' }
  let(:precision) { 'ns' }

  let(:raw_line) { 'SENEC inverter_power=123i 1711122334455' }

  before { allow(InfluxWriter).to receive(:write) }

  it 'saves the parsed field to the store (SQLite)' do
    processor.process(raw_line)

    rows = STORE.db[:sensor_data].all
    expect(rows.size).to eq(1)
    expect(rows.first).to include(
      measurement: 'SENEC',
      field: 'inverter_power',
      value_bool: nil,
      value_float: nil,
      value_int: 123,
      value_string: nil,
      timestamp: 1_711_122_334_455,
    )
  end

  it 'forwards the original line to InfluxWriter' do
    processor.process(raw_line)

    expect(InfluxWriter).to have_received(:write).with(
      raw_line,
      influx_token:,
      bucket:,
      org:,
      precision:,
    )
  end
end
