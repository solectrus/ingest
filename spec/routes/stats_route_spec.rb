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

    context 'when not logged in' do
      it 'redirects to login' do
        get '/'

        expect(last_response).to be_redirect
      end
    end

    context 'when logged in' do
      before { login }

      it 'renders the homepage with stats' do
        get '/'

        expect(last_response).to be_ok
        expect(last_response.body).to include('Incoming')
        expect(last_response.body).to include('Outgoing')
      end
    end
  end
end
