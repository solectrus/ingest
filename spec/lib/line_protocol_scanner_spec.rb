describe LineProtocolScanner do
  describe '.split' do
    it 'splits at plain delimiters' do
      expect(described_class.split('a,b,c', ',')).to eq(%w[a b c])
    end

    it 'keeps escaped delimiters in place' do
      expect(described_class.split('a\\,b,c', ',')).to eq(['a\\,b', 'c'])
    end

    it 'keeps a backslash that escapes nothing special' do
      expect(described_class.split('C:\\path,c', ',')).to eq(['C:\\path', 'c'])
    end

    it 'keeps delimiters inside a string field value' do
      expect(described_class.split('a="x,y",b=1', ',', field_set: true)).to eq(['a="x,y"', 'b=1'])
    end

    it 'keeps an escaped quote from closing a string field value' do
      expect(described_class.split('a="x\\",y",b=1', ',', field_set: true)).to eq(['a="x\\",y"', 'b=1'])
    end

    # Line protocol accepts a quote in a measurement, tag or field key and
    # reads it as part of the name, so it must not open a string value.
    it 'treats a quote in a field key as literal' do
      expect(described_class.split('my"key=1,other=2', ',', field_set: true)).to eq(['my"key=1', 'other=2'])
    end

    it 'treats a quote as literal outside the field set' do
      expect(described_class.split('a="x,y",b=1', ',')).to eq(['a="x', 'y"', 'b=1'])
    end

    it 'returns the whole string when the delimiter does not occur' do
      expect(described_class.split('abc', ',')).to eq(%w[abc])
    end

    it 'keeps empty parts' do
      expect(described_class.split('a,,b', ',')).to eq(['a', '', 'b'])
    end
  end

  describe '.split_once' do
    it 'cuts at the first unescaped delimiter' do
      expect(described_class.split_once('a b c', ' ')).to eq(['a', 'b c'])
    end

    it 'skips an escaped delimiter' do
      expect(described_class.split_once('a\\ b c', ' ')).to eq(['a\\ b', 'c'])
    end

    it 'returns nil when the delimiter does not occur' do
      expect(described_class.split_once('abc', ' ')).to be_nil
    end
  end
end
