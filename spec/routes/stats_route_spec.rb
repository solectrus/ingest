describe StatsRoute do
  def app
    StatsRoute.new
  end

  describe 'GET /' do
    before do
      Target.create!(
        influx_token: 't',
        bucket: 'b',
        org: 'o',
      )

      Incoming.create!(
        target: Target.first,
        measurement: 'test',
        field: 'val',
        value: 42,
        timestamp: Time.current.to_i * 1_000_000_000,
      )

      Outgoing.create!(
        target: Target.first,
        line_protocol: 'line',
        created_at: Time.current,
      )
    end

    context 'without password' do
      it 'returns 401 Unauthorized' do
        get '/'

        expect(last_response).to be_unauthorized
        expect(last_response.body).to include('Unlock')
      end
    end

    context 'when password in param is valid' do
      it 'redirects' do
        get "/?unlock=#{ENV.fetch('STATS_PASSWORD', nil)}"

        expect(last_response).to be_redirect
        expect(last_response.headers['Set-Cookie']).to include('password')
      end
    end

    context 'when password in param is invalid' do
      it 'redirects' do
        get '/?unlock=invalid_password'

        expect(last_response).to be_unauthorized
        expect(last_response.body).to include('Unlock')
      end
    end

    context 'when password in cookie is invalid' do
      before do
        rack_mock_session.cookie_jar['password'] = 'invalid_password'
      end

      it 'returns 401 Unauthorized' do
        get '/'

        expect(last_response).to be_unauthorized
        expect(last_response.body).to include('Unlock')
      end
    end

    context 'when password in cookie is valid' do
      before do
        rack_mock_session.cookie_jar['password'] = ENV.fetch('STATS_PASSWORD', nil)
      end

      it 'renders the homepage with stats' do
        get '/'

        expect(last_response).to be_ok
        expect(last_response.body).to include('Incoming')
        expect(last_response.body).to include('Outgoing')
      end
    end
  end
end
