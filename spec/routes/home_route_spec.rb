describe HomeRoute do
  def app
    HomeRoute.new
  end

  describe 'GET /' do
    before do
      Target.create!(influx_token: 't', bucket: 'b', org: 'o', precision: 'ns')

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

    context 'without credentials' do
      it 'returns 401 Unauthorized' do
        get '/'

        expect(last_response.status).to eq(401)
      end
    end

    context 'when credentials are invalid' do
      before { basic_authorize('invalid_user', 'invalid_password') }

      it 'returns 401 Unauthorized' do
        get '/'

        expect(last_response.status).to eq(401)
      end
    end

    context 'when username and password are set' do
      before do
        basic_authorize(
          ENV.fetch('STATS_USERNAME', nil),
          ENV.fetch('STATS_PASSWORD', nil),
        )
      end

      it 'renders the homepage with stats' do
        get '/'

        expect(last_response.status).to eq(200)
        expect(last_response.body).to include('SOLECTRUS :: Ingest')
        expect(last_response.body).to include('Incoming')
        expect(last_response.body).to include('Outgoing')
      end
    end
  end
end
