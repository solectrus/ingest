describe Point do
  describe '.parse' do
    subject(:point) { described_class.parse(line) }

    context 'with timestamp' do
      let(:line) do
        'SENEC application_version="0826",bat_charge_current=-0.3,bat_fuel_charge=100.0,' \
          'bat_power_minus=19i,bat_power_plus=0i,bat_voltage=57.2,case_temp=32.5,' \
          'current_state="AKKU VOLL",current_state_code=13i,current_state_ok=true,ev_connected=false,' \
          'grid_power_minus=808i,grid_power_plus=0i,house_power=459i,inverter_power=1249i,' \
          'measure_time=1742655477i,mpp1_power=620i,mpp2_power=0i,mpp3_power=628i,' \
          'power_ratio=100.0,response_duration=9i,wallbox_charge_power=0i,wallbox_charge_power0=0i,' \
          'wallbox_charge_power1=0i,wallbox_charge_power2=0i,wallbox_charge_power3=0i 1742655477'
      end

      it 'parses name' do
        expect(point.name).to eq('SENEC')
      end

      it 'parses time' do
        expect(point.time).to eq(1_742_655_477)
      end

      it 'parses fields' do
        expect(point.fields).to include('inverter_power' => 1249)
        expect(point.fields).to include('ev_connected' => false)
        expect(point.fields).to include('current_state_ok' => true)
        expect(point.fields).to include('current_state' => 'AKKU VOLL')
        expect(point.fields).to include('case_temp' => 32.5)
      end
    end

    context 'without timestamp' do
      let(:line) do
        'Car,model=Zoe battery_autonomy=117i,battery_level=44i,charging_remaining_time=160i,' \
          'charging_status=0.0,max_range=266i,mileage=50294.0,plug_status=0i'
      end

      it 'parses name' do
        expect(point.name).to eq('Car')
      end

      it 'parses time' do
        expect(point.time).to be_nil
      end

      it 'parses fields' do
        expect(point.fields).to include('mileage' => 50_294.0)
      end
    end
  end
end
