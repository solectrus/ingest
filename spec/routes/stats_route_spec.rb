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

      # The write route takes any token, so anybody who reaches the port can
      # choose the measurement and field names. They must not run as markup in
      # the browser of the reader.
      it 'escapes a measurement and a field name' do
        Target.first.incomings.create!(
          measurement: '<script>alert(1)</script>',
          field: '<img src=x onerror=alert(2)>',
          value: 1,
          timestamp: Time.current.to_i * 1_000_000_000,
        )

        get '/'

        expect(last_response.body).not_to include('<script>alert(1)</script>')
        expect(last_response.body).not_to include('<img src=x onerror=alert(2)>')
        expect(last_response.body).to include('&lt;script&gt;alert(1)&lt;/script&gt;')
      end
    end
  end
end
