describe Outgoing do
  subject(:outgoing) do
    described_class.create!(
      target: target,
      line_protocol: 'measurement field=1i 1000000',
    )
  end

  let(:target) do
    Target.create!(
      influx_token: 'test-token',
      bucket: 'test-bucket',
      org: 'test-org',
    )
  end

  describe 'validations' do
    it 'is valid with valid attributes' do
      expect(outgoing).to be_valid
    end

    it 'is invalid without line_protocol' do
      outgoing.line_protocol = nil
      expect(outgoing).not_to be_valid
      expect(outgoing.errors[:line_protocol]).to include("can't be blank")
    end

    it 'is invalid without target (target_id nil)' do
      outgoing.target_id = nil
      expect(outgoing).not_to be_valid
      expect(outgoing.errors[:target]).to include('must exist')
    end
  end
end
