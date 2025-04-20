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
        expect(last_response.cookies['password']).to eq([valid_password])
      end

      it 'redirects to the target page' do
        expect(last_response).to be_redirect
        follow_redirect!
        expect(last_request.path).to eq('/')
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
