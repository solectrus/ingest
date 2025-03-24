describe Sensor do
  subject(:sensor) do
    described_class.new(
      target: target,
      measurement: 'SENEC',
      field: 'inverter_power',
      timestamp: 1000,
    )
  end

  let(:target) do
    Target.create!(
      influx_token: 'test-token',
      bucket: 'test-bucket',
      org: 'test-org',
      precision: 'ns',
    )
  end

  describe 'validations' do
    it 'validates presence of measurement' do
      sensor.measurement = nil
      expect(sensor).not_to be_valid
      expect(sensor.errors[:measurement]).to include("can't be blank")
    end

    it 'validates presence of field' do
      sensor.field = nil
      expect(sensor).not_to be_valid
      expect(sensor.errors[:field]).to include("can't be blank")
    end

    it 'validates presence of timestamp' do
      sensor.timestamp = nil
      expect(sensor).not_to be_valid
      expect(sensor.errors[:timestamp]).to include("can't be blank")
    end
  end

  describe '#value=' do
    it 'sets the correct field when Integer' do
      sensor.value = 42
      expect(sensor.value_int).to eq(42)
    end

    it 'sets the correct field when Float' do
      sensor.value = 42.5
      expect(sensor.value_float).to eq(42.5)
    end

    it 'sets the correct field when TrueClass' do
      sensor.value = true
      expect(sensor.value_bool).to be(true)
    end

    it 'sets the correct field when FalseClass' do
      sensor.value = false
      expect(sensor.value_bool).to be(false)
    end

    it 'sets the correct field when String' do
      sensor.value = 'test'
      expect(sensor.value_string).to eq('test')
    end

    it 'adds an error if the value type is invalid' do
      sensor.value = nil

      expect(sensor).not_to be_valid
      expect(sensor.errors[:value]).to include("can't be blank")
    end
  end

  describe '#value' do
    it 'returns the value_int when Integer' do
      sensor.value_int = 42
      expect(sensor.value).to eq(42)
    end

    it 'returns the value_float when Float' do
      sensor.value_float = 42.5
      expect(sensor.value).to eq(42.5)
    end

    it 'returns the value_string when String' do
      sensor.value_string = 'test'
      expect(sensor.value).to eq('test')
    end

    it 'returns the value_bool when TrueClass or FalseClass' do
      sensor.value_bool = true
      expect(sensor.value).to be(true)
    end
  end

  describe '#mark_synced!' do
    before do
      sensor.value = 42
      sensor.save!
    end

    it 'marks the sensor as synced' do
      expect(sensor.synced).to be(false)
      sensor.mark_synced!
      expect(sensor.synced).to be(true)
    end
  end

  describe '.interpolate' do
    before do
      described_class.create!(
        target: target,
        measurement: 'SENEC',
        field: 'inverter_power',
        timestamp: 1000,
        value: 100,
      )

      described_class.create!(
        target: target,
        measurement: 'SENEC',
        field: 'inverter_power',
        timestamp: 2000,
        value: 200,
      )
    end

    it 'interpolates values correctly between two points' do
      result =
        described_class.interpolate(
          measurement: 'SENEC',
          field: 'inverter_power',
          timestamp: 1500,
        )
      expect(result).to eq(150.0)
    end

    it 'returns the exact value if timestamp matches' do
      result =
        described_class.interpolate(
          measurement: 'SENEC',
          field: 'inverter_power',
          timestamp: 1000,
        )
      expect(result).to eq(100)
    end

    it 'returns nil if no interpolation is possible' do
      result =
        described_class.interpolate(
          measurement: 'SENEC',
          field: 'inverter_power',
          timestamp: 3000,
        )
      expect(result).to be_nil
    end
  end

  describe '.cleanup' do
    let!(:old_sensor) do
      time_13h_ago = (Time.now.to_i - (13 * 60 * 60)) * 1_000_000_000

      described_class.create!(
        target: target,
        measurement: 'SENEC',
        field: 'inverter_power',
        timestamp: time_13h_ago,
        value: 100,
      )
    end

    let(:fresh_sensor) do
      now = Time.now.to_i * 1_000_000_000

      described_class.create!(
        target: target,
        measurement: 'SENEC',
        field: 'inverter_power',
        timestamp: now,
        value: 200,
      )
    end

    it 'deletes records older than the default timestamp' do
      described_class.cleanup

      expect(fresh_sensor.reload).to be_present
      expect { old_sensor.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
