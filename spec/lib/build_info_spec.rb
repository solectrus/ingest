describe BuildInfo do
  around do |example|
    described_class.instance_variable_set(:@version, nil)
    described_class.instance_variable_set(:@revision, nil)
    described_class.instance_variable_set(:@built_at, nil)
    described_class.instance_variable_set(:@revision_short, nil)
    described_class.instance_variable_set(:@to_s, nil)

    original_env = ENV.to_hash
    ENV.replace(original_env.merge(env_vars))
    example.run
  ensure
    ENV.replace(original_env)
  end

  context 'with all environment variables present' do
    let(:env_vars) do
      {
        'VERSION' => '1.2.3',
        'REVISION' => 'abc123456789',
        'BUILDTIME' => '2025-03-29T08:00:00Z',
        'TZ' => 'Europe/Berlin',
      }
    end

    it 'returns the correct version' do
      expect(described_class.version).to eq('1.2.3')
    end

    it 'returns the short revision' do
      expect(described_class.revision_short).to eq('abc1234')
    end

    it 'formats local_built_at correctly' do
      expect(described_class.local_built_at).to match(
        /\A2025-03-29 09:00 C[ET]{2}\z/,
      )
    end

    it 'returns a full formatted string' do
      expect(described_class.to_s).to include(
        'Version 1.2.3 (abc1234), built at 2025-03-29',
      )
    end
  end

  context 'with missing environment variables' do
    let(:env_vars) { {} }

    it 'returns nils for raw values' do
      expect(described_class.version).to eq('unknown')
      expect(described_class.revision).to be_nil
      expect(described_class.built_at).to be_nil
    end

    it 'returns "unknown" in to_s' do
      expect(described_class.to_s).to eq('Version unknown')
    end
  end

  context 'with invalid timezone' do
    let(:env_vars) do
      {
        'VERSION' => '1.0.0',
        'REVISION' => 'abcdef123456',
        'BUILDTIME' => '2025-03-29T08:00:00Z',
        'TZ' => 'invalid/timezone',
      }
    end

    it 'falls back to raw UTC string on invalid timezone' do
      expect(described_class.local_built_at).to eq('2025-03-29T08:00:00Z')
    end
  end
end
