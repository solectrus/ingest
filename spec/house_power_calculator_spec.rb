require 'house_power_calculator'

describe HousePowerCalculator do
  let(:now_ns) { 1_000_000_000_000_000_000 }
  let(:old_ns) { now_ns - ((5 * 60 * 1_000_000_000) + 1) }

  before do
    ENV['INFLUX_SENSOR_INVERTER_POWER'] = 'SENEC:inverter_power'
    ENV['INFLUX_SENSOR_GRID_IMPORT_POWER'] = 'SENEC:grid_import'
    ENV['INFLUX_SENSOR_BATTERY_DISCHARGING_POWER'] = 'SENEC:bat_discharge'
    ENV['INFLUX_SENSOR_BATTERY_CHARGING_POWER'] = 'SENEC:bat_charge'
    ENV['INFLUX_SENSOR_GRID_EXPORT_POWER'] = 'SENEC:grid_export'
    ENV['INFLUX_SENSOR_WALLBOX_POWER'] = 'SENEC:wallbox'
    ENV['INFLUX_SENSOR_HEATPUMP_POWER'] = 'Heatpump:power'
    ENV['INFLUX_SENSOR_HOUSE_POWER'] = 'SENEC:house_power'

    described_class.instance_variable_set(:@cache, StateCache.new)
  end

  it 'calculates house_power correctly when sufficient fresh data is available' do
    fresh = [
      "SENEC inverter_power=3000 #{now_ns}",
      "SENEC grid_import=200 #{now_ns}",
      "SENEC bat_discharge=500 #{now_ns}",
      "SENEC bat_charge=100 #{now_ns}",
      "SENEC grid_export=300 #{now_ns}",
      "SENEC wallbox=50 #{now_ns}",
      "Heatpump power=150 #{now_ns}",
    ]
    described_class.process_lines(fresh)

    trigger = "SENEC house_power=0 #{now_ns}"
    result = described_class.process_lines([trigger])

    expect(result.first).to include('house_power=3100')
  end

  it 'leaves house_power unchanged if required inputs are missing or outdated' do
    old = "SENEC inverter_power=9999 #{old_ns}"
    fresh = "SENEC grid_import=200 #{now_ns}"
    described_class.process_lines([old, fresh])

    trigger = "SENEC house_power=0 #{now_ns}"
    result = described_class.process_lines([trigger])

    # Calculation fails, line must stay unchanged
    expect(result.first).to eq(trigger)
  end

  it 'uses the latest cached value if fresh and valid' do
    described_class.process_lines(["SENEC inverter_power=100 #{old_ns}"])
    described_class.process_lines(["SENEC inverter_power=500 #{now_ns}", "SENEC grid_import=200 #{now_ns}",
                                   "SENEC bat_discharge=300 #{now_ns}",])
    described_class.process_lines(["SENEC bat_charge=100 #{now_ns}", "SENEC grid_export=50 #{now_ns}",
                                   "SENEC wallbox=50 #{now_ns}", "Heatpump power=50 #{now_ns}",])

    trigger = "SENEC house_power=0 #{now_ns}"
    result = described_class.process_lines([trigger])

    # Calculation: 500 + 200 + 300 = 1000 (incoming)
    # Outgoing: 100 + 50 + 50 + 50 = 250
    # 1000 - 250 = 750
    expect(result.first).to include('house_power=750')
  end
end
