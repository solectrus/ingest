describe LastCalculation do
  def record(timestamp_ns, result)
    described_class.record(
      timestamp_ns:,
      terms: HousePowerFormula.terms(inverter_power: result),
      result:,
      source: :cache,
    )
  end

  describe '.read' do
    it 'answers nothing while nothing is recorded' do
      expect(described_class.read).to be_nil
    end
  end

  describe '.record' do
    it 'keeps what it is given' do
      record(2_000_000_000, 500)

      expect(described_class.read).to include(
        timestamp_ns: 2_000_000_000,
        result: 500,
        source: :cache,
      )
    end

    it 'replaces the record with a newer timestamp' do
      record(2_000_000_000, 500)
      record(3_000_000_000, 700)

      expect(described_class.read).to include(
        timestamp_ns: 3_000_000_000,
        result: 700,
      )
    end

    # A backfill computes old timestamps now, and the page shows the present.
    # Without the guard, a batch of yesterday would take over the page.
    it 'ignores a timestamp older than the one it holds' do
      record(3_000_000_000, 700)
      record(2_000_000_000, 500)

      expect(described_class.read).to include(
        timestamp_ns: 3_000_000_000,
        result: 700,
      )
    end

    # The same timestamp carries the same moment, so there is nothing newer to
    # show.
    it 'ignores a timestamp equal to the one it holds' do
      record(3_000_000_000, 700)
      record(3_000_000_000, 999)

      expect(described_class.read).to include(result: 700)
    end
  end
end
