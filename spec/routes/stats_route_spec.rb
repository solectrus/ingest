describe StatsRoute do
  def app
    StatsRoute.new
  end

  # INFLUX_EXCLUDE_FROM_HOUSE_POWER of the test environment names it.
  let(:excluded_key) { SensorEnvConfig.exclude_from_house_power_keys.first }

  describe 'GET /' do
    before do
      Target.create!(
        influx_token: 't',
        bucket: 'b',
        org: 'o',
      )

      # Every configured sensor needs a line, otherwise the page reports the
      # missing ones and the badge is no longer quiet.
      SensorEnvConfig.config.each_value do |sensor|
        Incoming.create!(
          target: Target.first,
          measurement: sensor[:measurement],
          field: sensor[:field],
          value: 42,
          timestamp: Time.current.to_i * 1_000_000_000,
        )
      end

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
        expect(last_response.body).to include('Buffer')
        expect(last_response.body).to include('InfluxDB')
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

      it 'shows a quiet badge while every value is fine' do
        get '/'

        expect(last_response.body).to include('class="brand__live "')
        expect(last_response.body).to include('>Live</span>')
      end

      # A bucket and an org are as long as somebody makes them, so each one
      # gets a row with a label of its own.
      it 'names the bucket, the org and the tokens of a target' do
        get '/'

        expect(last_response.body).to include('<dt>Bucket</dt>')
        expect(last_response.body).to include('<dt>Org</dt>')
        expect(last_response.body).to include('<dt>Tokens</dt>')
      end

      # The two groups of the configuration look the same in one list, so each
      # one carries a title of its own.
      it 'gives every group of sensors a card of its own' do
        get '/'

        expect(last_response.body).to include('The house power</h3>')
        expect(last_response.body).to include('Excluded from the house power')
        expect(last_response.body).to include(excluded_key.to_s)
      end

      # Ingest calculates the house power, so the sensor of the collector is
      # the result of the formula and not a term of it.
      it 'marks the house power as the result' do
        get '/'

        expect(last_response.body).to include(
          'house_power <small>(result)</small>',
        )
      end

      # A sensor that the house power excludes can be absent on purpose. Such
      # a sensor must not colour the badge.
      it 'stays quiet while an excluded sensor has no data' do
        sensor = SensorEnvConfig[excluded_key]
        Incoming.where(
          measurement: sensor[:measurement], field: sensor[:field],
        ).delete_all

        get '/'

        expect(last_response.body).to include('class="brand__live "')
        expect(last_response.body).not_to include('without data')
      end

      # The badge renders in the header, before the fields of the page. Its
      # colour must still show what those fields say. The text stays "Live".
      it 'shows a red badge when a line was lost' do
        Stats.inc(:outgoing_dropped)

        get '/'

        expect(last_response.body).to include('class="brand__live crit"')
        expect(last_response.body).to include('>Live</span>')
      end
    end
  end
end
