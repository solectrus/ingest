describe Database do
  describe '.compact!' do
    it 'rebuilds the database file' do
      expect { described_class.compact! }.not_to raise_error
    end
  end

  # The mode of the file on disk depends on the version that wrote it, so both
  # answers come from a stub.
  describe '.auto_vacuum_incremental?' do
    def stub_auto_vacuum(mode)
      allow(ActiveRecord::Base.connection).to receive(:select_value).with(
        'PRAGMA auto_vacuum',
      ).and_return(mode)
    end

    it 'is true for a database that holds the mode' do
      stub_auto_vacuum(Database::AUTO_VACUUM_INCREMENTAL)

      expect(described_class).to be_auto_vacuum_incremental
    end

    it 'is false for a database without the mode' do
      stub_auto_vacuum(0)

      expect(described_class).not_to be_auto_vacuum_incremental
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
