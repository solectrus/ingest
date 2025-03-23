require 'sqlite3'
require 'time'

describe SensorDataStore do
  let(:store) { SensorDataStore.new }
  let(:now) { Time.now.to_i }

  it 'stores and interpolates int and float values' do
    store.store(measurement: 'SENEC', field: 'inverter_power', timestamp: now, value: 1000)
    store.store(measurement: 'SENEC', field: 'inverter_power', timestamp: now + 60, value: 2000)

    result = store.interpolate(measurement: 'SENEC', field: 'inverter_power', target_ts: now + 30)
    expect(result).to eq(1500.0)
  end

  it 'uses nearest value if only one side available' do
    store.store(measurement: 'SENEC', field: 'inverter_power', timestamp: now, value: 1000)

    result = store.interpolate(measurement: 'SENEC', field: 'inverter_power', target_ts: now + 60)
    expect(result).to eq(1000.0)
  end

  it 'returns 0.0 if no value is found' do
    result = store.interpolate(measurement: 'SENEC', field: 'inverter_power', target_ts: now)
    expect(result).to eq(0.0)
  end

  it 'cleans up old data' do
    store.store(measurement: 'SENEC', field: 'inverter_power', timestamp: now - 5000, value: 1000)
    store.cleanup(now - 1000)

    result = store.interpolate(measurement: 'SENEC', field: 'inverter_power', target_ts: now)
    expect(result).to eq(0.0)
  end
end
