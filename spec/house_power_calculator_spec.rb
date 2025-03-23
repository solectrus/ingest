require 'house_power_calculator'

describe HousePowerCalculator do
  let(:now_ns) { 1_000_000_000_000_000_000 }
  let(:old_ns) { now_ns - ((5 * 60 * 1_000_000_000) + 1) }

  it 'calculates house_power correctly when sufficient fresh data is available' do
    fresh = [
      "SENEC inverter_power=3000 #{now_ns}",
      "SENEC grid_power_plus=200 #{now_ns}",
      "SENEC bat_power_minus=500 #{now_ns}",
      "SENEC bat_power_plus=100 #{now_ns}",
      "SENEC grid_power_minus=300 #{now_ns}",
      "SENEC wallbox_charge_power=50 #{now_ns}",
      "Heatpump power=150 #{now_ns}",
    ]
    described_class.process_lines(fresh)

    trigger = "SENEC house_power=0 #{now_ns}"
    result = described_class.process_lines([trigger])

    # incoming = 3000 + 200 + 500 = 3700
    # outgoing = 100 + 300 + 50 + 150 = 600
    # house_power = 3700 - 600 = 3100
    expect(result.first).to include('house_power=3100')
  end

  it 'leaves house_power unchanged if required inputs are missing or outdated' do
    old = "SENEC inverter_power=9999 #{old_ns}"
    fresh = "SENEC grid_power_plus=200 #{now_ns}"
    described_class.process_lines([old, fresh])

    trigger = "SENEC house_power=0 #{now_ns}"
    result = described_class.process_lines([trigger])

    # Calculation fails, line must stay unchanged
    expect(result.first).to eq(trigger)
  end

  it 'uses the latest cached value if fresh and valid' do
    described_class.process_lines(["SENEC inverter_power=100 #{old_ns}"])

    described_class.process_lines(
      [
        "SENEC inverter_power=500 #{now_ns}",
        "SENEC grid_power_plus=200 #{now_ns}",
        "SENEC bat_power_minus=300 #{now_ns}",
      ],
    )

    described_class.process_lines(
      [
        "SENEC bat_power_plus=100 #{now_ns}",
        "SENEC grid_power_minus=50 #{now_ns}",
        "SENEC wallbox_charge_power=50 #{now_ns}",
        "Heatpump power=50 #{now_ns}",
      ],
    )

    trigger = "SENEC house_power=0 #{now_ns}"
    result = described_class.process_lines([trigger])

    # incoming = 500 + 200 + 300 = 1000
    # outgoing = 100 + 50 + 50 + 50 = 250
    # house_power = 1000 - 250 = 750
    expect(result.first).to include('house_power=750')
  end
end
