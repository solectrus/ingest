describe EncodingHelper do
  describe '.clean_utf8' do
    it 'returns a valid UTF-8 string unchanged' do
      input = 'Hello ☀️'
      output = described_class.clean_utf8(input)
      expect(output).to eq('Hello ☀️')
      expect(output.encoding).to eq(Encoding::UTF_8)
    end

    it 'forces encoding if input is ASCII-8BIT but valid UTF-8' do
      input = 'Grüße'.dup.force_encoding('ASCII-8BIT')
      output = described_class.clean_utf8(input)
      expect(output).to eq('Grüße')
      expect(output.encoding).to eq(Encoding::UTF_8)
    end

    it 'replaces invalid characters with ?' do
      input = "bad\xE2input".dup.force_encoding('ASCII-8BIT')
      output = described_class.clean_utf8(input)
      expect(output).to eq('bad?input')
      expect(output.encoding).to eq(Encoding::UTF_8)
    end

    it 'does not modify the original string' do
      original = 'test'.dup
      described_class.clean_utf8(original)
      expect(original).to eq('test')
    end
  end
end
