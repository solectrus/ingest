describe Stats do
  before do
    described_class.reset!
  end

  it 'increments counters correctly' do
    expect { described_class.inc(:foo) }.to change { described_class.counter(:foo) }.from(0).to(1)
    expect { described_class.inc(:foo) }.to change { described_class.counter(:foo) }.from(1).to(2)
  end

  it 'resets a single key' do
    described_class.inc(:a)
    described_class.inc(:b)

    described_class.reset!(:a)
    expect(described_class.counter(:a)).to eq(0)
    expect(described_class.counter(:b)).to eq(1)
  end

  it 'resets all keys' do
    described_class.inc(:x)
    described_class.inc(:y)
    described_class.reset!

    expect(described_class.counter(:x)).to eq(0)
    expect(described_class.counter(:y)).to eq(0)
  end

  it 'is thread-safe under concurrent access' do
    threads = Array.new(10) do
      Thread.new do
        1000.times { described_class.inc(:concurrent) }
      end
    end
    threads.each(&:join)

    expect(described_class.counter(:concurrent)).to eq(10_000)
  end

  describe '.counters_by' do
    before do
      described_class.inc(:http_response_200)
      described_class.inc(:http_response_500)
      described_class.inc(:other)
    end

    it 'returns counters matching a prefix' do
      result = described_class.counters_by(:http_response)
      expect(result).to eq(http_response_200: 1, http_response_500: 1)
    end
  end
end
