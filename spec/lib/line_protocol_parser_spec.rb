describe LineProtocolParser do
  describe '#parse' do
    it 'rejects a line with an empty field set' do
      expect { described_class.new('M  1000').parse }.to raise_error(
        LineProtocolParser::InvalidLineProtocolError,
      )
    end
  end
end
