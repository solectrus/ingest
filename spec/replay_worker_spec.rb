describe ReplayWorker do
  let(:influx_writer) { class_double(InfluxWriter).as_stubbed_const }

  before do
    target_id =
      STORE.save_target(
        influx_token: 'test-token',
        bucket: 'test-bucket',
        org: 'test-org',
      )

    STORE.save(
      measurement: 'SENEC',
      field: 'inverter_power',
      timestamp: 1_000_000_000,
      value: 100,
      target_id:,
    )

    STORE.save(
      measurement: 'Heatpump',
      field: 'power',
      timestamp: 2_000_000_000,
      value: 200,
      target_id:,
    )
  end

  it 'replays unsynced data to InfluxDB and marks as synced' do
    allow(InfluxWriter).to receive(:write).and_return(true)

    described_class.new(batch_size: 10).replay!

    expect(InfluxWriter).to have_received(:write).once

    synced = STORE.db[:sensor_data].exclude(synced: true).count
    expect(synced).to eq(0)
  end
end
