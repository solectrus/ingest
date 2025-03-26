describe Line do
  let(:line) do
    'SENEC application_version="0826",bat_charge_current=-0.3,bat_fuel_charge=100.0,' \
      'bat_power_minus=19i,bat_power_plus=0i,bat_voltage=57.2,case_temp=32.5,' \
      'current_state="AKKU VOLL",current_state_code=13i,current_state_ok=true,ev_connected=false,' \
      'grid_power_minus=808i,grid_power_plus=0i,house_power=459i,inverter_power=1249i,' \
      'measure_time=1742655477i,mpp1_power=620i,mpp2_power=0i,mpp3_power=628i,' \
      'power_ratio=100.0,response_duration=9i,wallbox_charge_power=0i,wallbox_charge_power0=0i,' \
      'wallbox_charge_power1=0i,wallbox_charge_power2=0i,wallbox_charge_power3=0i 1742655477'
  end

  describe '.parse' do
    subject(:parsed) { described_class.parse(line) }

    it 'parses measurement' do
      expect(parsed.measurement).to eq('SENEC')
    end

    it 'parses timestamp' do
      expect(parsed.timestamp).to eq(1_742_655_477)
    end

    it 'parses fields' do
      expect(parsed.fields).to include(inverter_power: 1249)
      expect(parsed.fields).to include(ev_connected: false)
      expect(parsed.fields).to include(current_state: 'AKKU VOLL')
    end
  end
end
