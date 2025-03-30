describe OutboxNotifier do
  let(:counter) { Concurrent::AtomicFixnum.new(0) }

  def start_waiting_thread
    Thread.new do
      OutboxNotifier.wait
      counter.increment
    end
  end

  def wait_for_thread(thread)
    Timeout.timeout(0.3) { thread.join }
  end

  context 'when notify! is called before wait' do
    before { described_class.notify! }

    it 'still wakes the waiting thread' do
      thread = start_waiting_thread
      wait_for_thread(thread)

      expect(counter.value).to eq(1)
    end
  end

  context 'when notify! is called after thread started waiting' do
    it 'wakes the thread normally' do
      thread = start_waiting_thread
      sleep 0.01

      described_class.notify!
      wait_for_thread(thread)

      expect(counter.value).to eq(1)
    end
  end

  context 'when multiple notify! calls are made before wait' do
    it 'does not result in multiple wake-ups' do
      5.times { described_class.notify! }

      thread = start_waiting_thread
      wait_for_thread(thread)

      expect(counter.value).to eq(1)
    end
  end

  context 'when notify! is never called' do
    it 'causes the thread to stay blocked (timeout)' do
      thread = start_waiting_thread

      expect do
        # Wait for a short time to see if the thread wakes up
        # This should raise a Timeout::Error because we don't call notify!
        Timeout.timeout(0.1) { thread.join }
      end.to raise_error(Timeout::Error)

      thread.kill
    end
  end
end
