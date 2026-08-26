describe StatsRoute do
  def app
    StatsRoute.new
  end

  # INFLUX_EXCLUDE_FROM_HOUSE_POWER of the test environment names it.
  let(:excluded_key) { SensorEnvConfig.exclude_from_house_power_keys.first }

  describe 'the stats page' do
    before do
      Target.create!(
        influx_token: 'super-secret',
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

        get '/sensors'

        expect(last_response.body).not_to include('<script>alert(1)</script>')
        expect(last_response.body).not_to include('<img src=x onerror=alert(2)>')
        expect(last_response.body).to include('&lt;script&gt;alert(1)&lt;/script&gt;')
      end

      # The page splits into tabs, and every tab has a path of its own. The
      # page reloads itself every 30 seconds, and only the URL survives that
      # reload.
      describe 'the tabs' do
        it 'opens the data path on the root path' do
          get '/'

          expect(last_response.body).to match(
            %r{href="/"\s+aria-current="page"},
          )
          expect(last_response.body).to include('>Incoming <small>')
        end

        it 'renders the tab that the path names' do
          get '/house-power'

          expect(last_response.body).to include('The formula')
          expect(last_response.body).not_to include('>Incoming <small>')
        end

        # A reader can type anything into the URL. Only the paths of the tabs
        # answer, so the app has no name to guess a template from.
        it 'answers 404 for an unknown path' do
          get '/layout'

          expect(last_response).to be_not_found
        end

        it 'renders every tab of the page' do
          StatsHelpers::TABS.each do |tab|
            get tab[:path]

            expect(last_response).to be_ok
          end
        end

        # A tab hides what it holds. Without the dot a reader sees the red
        # badge of the header and has to open every tab to find the fault.
        it 'marks the tab that carries a fault' do
          Stats.inc(:outgoing_dropped)

          get '/house-power'

          expect(last_response.body).to include(
            '<span class="tabs__dot crit"',
          )
        end

        it 'marks no tab while every value is fine' do
          get '/'

          expect(last_response.body).not_to include('tabs__dot')
        end
      end

      it 'shows a quiet badge while every value is fine' do
        get '/'

        expect(last_response.body).to include('class="brand__live "')
        expect(last_response.body).to include('>Live</span>')
      end

      # One row per target. The token is masked, and it is on the page so that
      # two collectors that write to one bucket are two rows a reader can tell
      # apart.
      it 'names the bucket, the org and the masked token of a target' do
        get '/'

        expect(last_response.body).to include('b / o / s......t')
        expect(last_response.body).not_to include('super-secret')
      end

      # The two groups of the configuration look the same in one list, so each
      # one carries a title of its own.
      it 'gives every group of sensors a card of its own' do
        get '/sensors'

        expect(last_response.body).to match(/card__title">\s*The house power\s/)
        expect(last_response.body).to include('Excluded from the house power')
        expect(last_response.body).to include(excluded_key.to_s)
      end

      # Ingest calculates the house power, so the sensor of the collector is
      # not a term of the formula. The row says what happens to it: this
      # configuration writes the result to the same field, so the incoming
      # value never reaches InfluxDB.
      it 'says that the house power is replaced' do
        get '/sensors'

        expect(last_response.body).to include(
          'house_power <small>(replaced)</small>',
        )
      end

      # A sensor that the house power excludes can be absent on purpose. Such
      # a sensor must not colour the badge.
      it 'stays quiet while an excluded sensor has no data' do
        sensor = SensorEnvConfig[excluded_key]
        Incoming.where(
          measurement: sensor[:measurement], field: sensor[:field],
        ).delete_all

        get '/sensors'

        expect(last_response.body).to include('class="brand__live "')
        expect(last_response.body).not_to include('without data')
      end

      # An empty buffer holds no line of any sensor, so the page cannot tell a
      # healthy sensor from one that nobody sends. It said "all 7 receive
      # data" there, and a fresh container thus read a wrong all-clear.
      it 'claims no sensor is fine while the buffer is empty' do
        Incoming.delete_all

        get '/sensors'

        expect(last_response.body).to include('(no data yet)')
        expect(last_response.body).not_to include('receive data')
      end

      # The formula above says "nothing calculated yet". A warning about the
      # last calculation would contradict it, and it stood in orange on a tab
      # that carries no fault.
      it 'warns about no subtraction before the first calculation' do
        get '/house-power'

        expect(last_response.body).to include('nothing calculated yet')
        expect(last_response.body).not_to include('cannot complete the subtraction')
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
