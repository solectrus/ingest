describe LoginRoute do
  include Rack::Test::Methods

  def app
    described_class.new
  end

  describe 'GET /login' do
    before { get '/login' }

    it 'returns 200 and renders login form' do
      expect(last_response).to be_ok
      expect(last_response.body).to include('form')
    end
  end

  describe 'POST /login' do
    let(:valid_password) { ENV.fetch('STATS_PASSWORD', nil) }

    context 'with valid password' do
      before { post '/login', password: valid_password }

      it 'sets the password cookie' do
        expect(last_response.cookies['password'].value).to eq([valid_password])
      end

      it 'redirects to the target page' do
        expect(last_response).to be_redirect
        follow_redirect!
        expect(last_request.path).to eq('/')
      end
    end

    context 'with a return_to cookie' do
      subject(:location) do
        set_cookie "return_to=#{return_to}"
        post '/login', password: valid_password

        last_response.headers['Location']
      end

      context 'with a path' do
        let(:return_to) { '/stats' }

        it { is_expected.to end_with('/stats') }
      end

      context 'with a foreign host' do
        let(:return_to) { 'https://evil.example.com/x' }

        it { is_expected.to end_with('/') }
        it { is_expected.not_to include('evil') }
      end

      context 'with a protocol-relative host' do
        let(:return_to) { '//evil.example.com/x' }

        it { is_expected.to end_with('/') }
        it { is_expected.not_to include('evil') }
      end
    end

    context 'with invalid password' do
      before { post '/login', password: 'invalid_password' }

      it 'does not set the password cookie' do
        expect(last_response.cookies['password']).to be_nil
      end

      it 'renders the login form with an error message' do
        expect(last_response.body).to include('Invalid, try again.')
      end
    end
  end
end
