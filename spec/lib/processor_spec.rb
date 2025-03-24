describe Processor do
  subject(:processor) do
    described_class.new(influx_token, bucket, org, precision)
  end

  let(:influx_token) { 'test-token' }
  let(:bucket) { 'test-bucket' }
  let(:org) { 'test-org' }
  let(:precision) { 'ns' }

  let(:raw_line) { 'SENEC inverter_power=123i 1711122334455' }

  before { allow(InfluxWriter).to receive(:write) }

  it 'saves the parsed field to the store (ActiveRecord)' do
    processor.run(raw_line)

    sensor = Sensor.first
    expect(sensor).to have_attributes(
      measurement: 'SENEC',
      field: 'inverter_power',
      value_int: 123,
      value_float: nil,
      value_bool: nil,
      value_string: nil,
      timestamp: 1_711_122_334_455,
    )
  end

  it 'forwards the original line to InfluxWriter' do
    processor.run(raw_line)

    expect(InfluxWriter).to have_received(:write).with(
      raw_line,
      influx_token:,
      bucket:,
      org:,
      precision:,
    )
  end
end
