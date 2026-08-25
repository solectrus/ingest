describe Target do
  subject(:target) do
    described_class.create!(
      influx_token: 'test-token',
      bucket: 'test-bucket',
      org: 'test-org',
      precision: InfluxDB2::WritePrecision::MILLISECOND,
    )
  end

  describe 'validations' do
    it 'is valid with valid attributes' do
      expect(target).to be_valid
    end

    it 'is invalid without influx_token' do
      target.influx_token = nil
      expect(target).not_to be_valid
    end

    it 'is invalid without bucket' do
      target.bucket = nil
      expect(target).not_to be_valid
    end

    it 'is invalid without org' do
      target.org = nil
      expect(target).not_to be_valid
    end

    it 'is invalid without precision' do
      target.precision = nil
      expect(target).not_to be_valid
    end
  end

  describe '.fetch' do
    let(:args) do
      {
        influx_token: 'test-token',
        bucket: 'test-bucket',
        org: 'test-org',
        precision: InfluxDB2::WritePrecision::SECOND,
      }
    end

    # Counts the statements on the targets table of a block.
    def target_queries
      count = 0
      subscriber =
        ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
          count += 1 if payload[:sql].include?('"targets"')
        end
      yield
      count
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    it 'creates the target on the first call' do
      expect { described_class.fetch(**args) }.to change(described_class, :count).by(1)
    end

    it 'returns the same row for the same arguments' do
      first = described_class.fetch(**args)

      expect(described_class.fetch(**args)).to be(first)
    end

    # The lookup ran per request, inside the transaction and the write lock.
    it 'reads the database once for repeated calls' do
      described_class.fetch(**args)

      expect(target_queries { 5.times { described_class.fetch(**args) } }).to be_zero
    end

    it 'tells two targets apart' do
      first = described_class.fetch(**args)
      second = described_class.fetch(**args, bucket: 'other-bucket')

      expect(first).not_to eq(second)
    end

    it 'finds a row that another process created' do
      existing = described_class.create!(**args)

      expect { expect(described_class.fetch(**args)).to eq(existing) }.not_to change(
        described_class,
        :count,
      )
    end
  end

  # Without it, `fetch` can create the same target twice.
  describe 'uniqueness' do
    it 'refuses a second row with the same arguments' do
      described_class.create!(
        influx_token: 'test-token',
        bucket: 'test-bucket',
        org: 'test-org',
      )

      expect do
        described_class.create!(
          influx_token: 'test-token',
          bucket: 'test-bucket',
          org: 'test-org',
        )
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe '#timestamp_ns' do
    it 'converts timestamp correctly based on precision' do
      expect(target.timestamp_ns(1_000)).to eq(1_000 * 1_000_000)
    end
  end

  describe '#timestamp' do
    it 'converts ns timestamp back based on precision' do
      expect(target.timestamp(1_000_000_000)).to eq(1_000)
    end
  end
end
