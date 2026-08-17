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
        expect(point.timestamp).to eq(1_742_655_477)
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

      it 'parses tags' do
        expect(point.tags).to eq('model' => 'Zoe')
      end

      it 'parses time' do
        expect(point.timestamp).to be_nil
      end

      it 'parses fields' do
        expect(point.fields).to include('mileage' => 50_294.0)
      end
    end

    context 'with an escaped space in the measurement' do
      let(:line) { 'PQ\\ Inverter power=115.5,temp=30.2 1755442800000000000' }

      it 'parses name' do
        expect(point.name).to eq('PQ Inverter')
      end

      it 'parses fields' do
        expect(point.fields).to eq('power' => 115.5, 'temp' => 30.2)
      end

      it 'parses time' do
        expect(point.timestamp).to eq(1_755_442_800_000_000_000)
      end
    end

    context 'with escaped separators in measurement, tags and field keys' do
      let(:line) do
        'Heat\\,Pump\\ 1,room=Living\\ Room,mode=eco\\=on power\\ total=42i,' \
          'label="a=b, c" 1755442800'
      end

      it 'parses name' do
        expect(point.name).to eq('Heat,Pump 1')
      end

      it 'parses tags' do
        expect(point.tags).to eq('room' => 'Living Room', 'mode' => 'eco=on')
      end

      it 'parses fields' do
        expect(point.fields).to eq('power total' => 42, 'label' => 'a=b, c')
      end

      it 'parses time' do
        expect(point.timestamp).to eq(1_755_442_800)
      end
    end

    context 'with a quoted string field value' do
      let(:line) { 'SENEC current_state="AKKU VOLL",note="say \\"hi\\" \\\\ ok" 1742655477' }

      it 'keeps spaces inside the quoted value' do
        expect(point.fields).to include('current_state' => 'AKKU VOLL')
      end

      it 'unescapes quotes and backslashes' do
        expect(point.fields).to include('note' => 'say "hi" \\ ok')
      end

      it 'parses time' do
        expect(point.timestamp).to eq(1_742_655_477)
      end
    end

    # Line protocol reads a backslash as an escape only before a character that
    # needs escaping. Elsewhere it stays literal, and two of them are one.
    context 'with backslashes' do
      it 'keeps a backslash before an ordinary character' do
        expect(described_class.parse('C:\\path value=1i').name).to eq('C:\\path')
      end

      it 'reads two backslashes as one' do
        expect(described_class.parse('a\\\\b value=1i').name).to eq('a\\b')
      end

      it 'reads three backslashes as two' do
        expect(described_class.parse('a\\\\\\b value=1i').name).to eq('a\\\\b')
      end
    end

    # Line protocol accepts quotes in a measurement, tag key, tag value and
    # field key, and reads them as part of the name.
    context 'with quotes outside a field value' do
      let(:line) { 'Say"Hi",room="Living\\ Room" my"key=1i' }

      it 'keeps the quotes in the measurement' do
        expect(point.name).to eq('Say"Hi"')
      end

      it 'keeps the quotes in the tag value' do
        expect(point.tags).to eq('room' => '"Living Room"')
      end

      it 'keeps the quotes in the field key' do
        expect(point.fields).to eq('my"key' => 1)
      end
    end

    # Line protocol defines five spellings per truth value, an `i` suffix for a
    # signed and a `u` suffix for an unsigned integer. A value that matches none
    # of the documented types must not become a plausible `0.0` reading.
    context 'with the documented value types' do
      {
        'state=t' => true,
        'state=T' => true,
        'state=true' => true,
        'state=True' => true,
        'state=TRUE' => true,
        'state=f' => false,
        'state=F' => false,
        'state=false' => false,
        'state=False' => false,
        'state=FALSE' => false,
        'power=42i' => 42,
        'power=-42i' => -42,
        'power=42u' => 42,
        'power=42' => 42.0,
        'power=4.2' => 4.2,
        'power=-4.2' => -4.2,
        'power=.5' => 0.5,
        'power=1e3' => 1000.0,
        'power=1.5e-3' => 0.0015,
      }.each do |field, expected|
        it "reads #{field} as #{expected.inspect}" do
          value = described_class.parse("M #{field}").fields.values.first

          expect(value).to eql(expected)
        end
      end
    end

    context 'with a malformed line' do
      {
        'without a field set' => 'SENEC',
        'on an empty line' => '   ',
        'on a field without a value' => 'SENEC power',
        'on an unescaped space inside the field set' => 'SENEC state=AKKU VOLL 1742655477',
        'on a non-numeric timestamp' => 'SENEC power=1i later',
        'on a value of no documented type' => 'SENEC power=abc',
        'on an empty value' => 'SENEC power=',
        'on a signed unsigned integer' => 'SENEC power=-42u',
        # `to_line_protocol` drops a field without a key, and one whose value
        # is infinite. A point that loses its last field serializes to nil,
        # and nil fails the NOT NULL column of the outbox with a 500.
        'on a field without a key' => 'SENEC =1i',
        'on a later field without a key' => 'SENEC power=1i,=2i',
        'on an exponent that overflows to infinity' => 'SENEC power=1e999',
        'on an exponent that overflows to -infinity' => 'SENEC power=-1e999',
      }.each do |reason, bad_line|
        it "raises #{reason}" do
          expect { described_class.parse(bad_line) }.to raise_error(LineProtocolParser::InvalidLineProtocolError)
        end
      end
    end

    # Ingest re-emits every point through `to_line_protocol`, so a parse that
    # loses an escape would write a different measurement than it received.
    describe 'round trip through to_line_protocol' do
      subject(:round_trip) { described_class.parse(described_class.parse(line).to_line_protocol) }

      let(:line) { 'PQ\\ Inverter,room=Living\\ Room power=115.5,label="a, b" 1755442800' }

      it 'keeps the measurement' do
        expect(round_trip.name).to eq('PQ Inverter')
      end

      it 'keeps the tags' do
        expect(round_trip.tags).to eq('room' => 'Living Room')
      end

      it 'keeps the fields' do
        expect(round_trip.fields).to eq('power' => 115.5, 'label' => 'a, b')
      end

      it 'keeps the time' do
        expect(round_trip.timestamp).to eq(1_755_442_800)
      end
    end
  end
end
