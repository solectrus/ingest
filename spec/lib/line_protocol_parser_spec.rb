describe LineProtocolParser do
  # The outbox groups queued lines by timestamp. Splitting on a bare space
  # reads the tail of a quoted string value, or an escaped measurement, as the
  # timestamp and groups the line under a value it never carried.
  describe '.timestamp' do
    {
      'a plain line' => ['M power=1i 1755442800', 1_755_442_800],
      'an escaped space in the measurement' => ['PQ\\ Inverter power=1i 1000', 1000],
      'an escaped space in a tag value' => ['M,room=Living\\ Room power=1i 42', 42],
      'a quoted value holding spaces' => ['M note="a b" 1755442800', 1_755_442_800],
      'a negative timestamp' => ['M power=1i -5', -5],
    }.each do |reason, (line, expected)|
      it "reads the timestamp of #{reason}" do
        expect(described_class.timestamp(line)).to eq(expected)
      end
    end

    {
      'a line without a timestamp' => 'M power=1i',
      'a quoted value ending in digits' => 'M note="x 1000"',
      'a line with no field set' => 'SENEC',
      'an empty line' => '   ',
      'a non-numeric timestamp' => 'M power=1i later',
    }.each do |reason, line|
      it "answers nil for #{reason}" do
        expect(described_class.timestamp(line)).to be_nil
      end
    end
  end
end
