describe StatsHelpers do
  include described_class

  describe '#format_duration' do
    it 'returns a dash for nil' do
      expect(format_duration(nil)).to eq('–')
    end

    it 'formats seconds only' do
      expect(format_duration(12)).to eq('12s')
    end

    it 'formats minutes and seconds' do
      expect(format_duration(75)).to eq('1m 15s')
    end

    it 'formats hours and minutes' do
      expect(format_duration(3600 + (2 * 60))).to eq('1h 2m')
    end

    it 'rounds down incomplete minutes and seconds' do
      expect(format_duration(3661)).to eq('1h 1m') # 1 hour, 1 min, 1 sec → no secs shown
    end
  end
end
