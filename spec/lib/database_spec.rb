describe Database do
  describe '.compact!' do
    it 'rebuilds the database file' do
      expect { described_class.compact! }.not_to raise_error
    end
  end

  describe '.thread_safe_write' do
    it 'returns the value of the block' do
      expect(described_class.thread_safe_write { 42 }).to eq(42)
    end

    it 'holds the lock while the block runs' do
      described_class.thread_safe_write do
        expect(Thread.new { described_class::WRITE_MUTEX.locked? }.value).to be(
          true,
        )
      end
    end

    context 'when called again in the same thread' do
      it 'does not raise' do
        expect do
          described_class.thread_safe_write do
            described_class.thread_safe_write { :ok }
          end
        end.not_to raise_error
      end

      it 'keeps holding the lock' do
        described_class.thread_safe_write do
          described_class.thread_safe_write do
            expect(
              Thread.new { described_class::WRITE_MUTEX.locked? }.value,
            ).to be(true)
          end
        end
      end

      it 'keeps holding the lock after the nested block' do
        described_class.thread_safe_write do
          described_class.thread_safe_write { :ok }

          expect(Thread.new { described_class::WRITE_MUTEX.locked? }.value).to be(
            true,
          )
        end
      end
    end
  end
end
