describe InfluxWriter do
  let(:params) do
    {
      influx_token: 'test-token',
      bucket: 'test-bucket',
      org: 'test-org',
      precision: InfluxDB2::WritePrecision::NANOSECOND,
    }
  end

  let(:lines) { ['test_measurement value=1 1234567890'] }

  let(:client_double) { instance_double(InfluxDB2::Client) }
  let(:write_api_double) { instance_double(InfluxDB2::WriteApi) }

  before do
    allow(InfluxDB2::Client).to receive(:new).and_return(client_double)
    allow(client_double).to receive(:create_write_api).and_return(
      write_api_double,
    )
    allow(client_double).to receive(:close!)
  end

  after { described_class.close_all }

  describe '.write' do
    it 'writes successfully to InfluxDB' do
      allow(write_api_double).to receive(:write)

      described_class.write(lines, **params)

      expect(write_api_double).to have_received(:write).with(
        data: lines.first,
        bucket: 'test-bucket',
        org: 'test-org',
        precision: InfluxDB2::WritePrecision::NANOSECOND,
      )
    end

    # InfluxDB2 sets InfluxError#code from Net::HTTP's response.code, which is
    # always a String. The tests therefore use String codes to match reality.
    it 'raises ClientError on 4xx response' do
      error =
        InfluxDB2::InfluxError.new(
          message: 'unauthorized',
          code: '401',
          reference: nil,
          retry_after: nil,
        )

      allow(write_api_double).to receive(:write).and_raise(error)

      expect { described_class.write(lines, **params) }.to raise_error(
        InfluxWriter::ClientError,
        /Client error \(401\)/,
      )
    end

    it 'raises ClientError on a field type conflict (partial write)' do
      error =
        InfluxDB2::InfluxError.new(
          message:
            'failure writing points to database: partial write: field type ' \
              'conflict: input field "heating_power" on measurement ' \
              '"heatpump" is type integer, already exists as type float ' \
              'dropped=7',
          code: '400',
          reference: nil,
          retry_after: nil,
        )

      allow(write_api_double).to receive(:write).and_raise(error)

      expect { described_class.write(lines, **params) }.to raise_error(
        InfluxWriter::ClientError,
        /field type conflict/,
      )
    end

    # A 429 is not a fault of the data: the token is temporarily over quota.
    # ClientError would make the caller drop the lines, so it must not be one.
    it 'raises ServerError on 429' do
      error =
        InfluxDB2::InfluxError.new(
          message: 'over quota',
          code: '429',
          reference: nil,
          retry_after: '90',
        )

      allow(write_api_double).to receive(:write).and_raise(error)

      expect { described_class.write(lines, **params) }.to raise_error(
        InfluxWriter::ServerError,
        /Over quota \(429\)/,
      )
    end

    it 'raises ServerError on 5xx response' do
      error =
        InfluxDB2::InfluxError.new(
          message: 'server error',
          code: '503',
          reference: nil,
          retry_after: nil,
        )

      allow(write_api_double).to receive(:write).and_raise(error)

      expect { described_class.write(lines, **params) }.to raise_error(
        InfluxWriter::ServerError,
        /Server error \(503\)/,
      )
    end

    it 'writes a single line given as a String' do
      allow(write_api_double).to receive(:write)

      described_class.write(lines.first, **params)

      expect(write_api_double).to have_received(:write).with(
        hash_including(data: lines.first),
      )
    end

    # The client catches the network errors itself and wraps them into an
    # InfluxError with an empty code, keeping the cause in #original. That
    # error went back to the caller unchanged before, and the caller rescues
    # ClientError and ServerError alone: a stopped InfluxDB thus escaped the
    # delivery path, the counter of failed writes stayed at zero, and the
    # queue got a full backtrace every second.
    it 'raises ServerError when the client wraps a network error' do
      error =
        InfluxDB2::InfluxError.from_error(
          Errno::ECONNREFUSED.new('connect(2) for "influxdb" port 8086'),
        )

      allow(write_api_double).to receive(:write).and_raise(error)

      expect { described_class.write(lines, **params) }.to raise_error(
        InfluxWriter::ServerError,
        /Network error.*Connection refused/,
      )
    end

    it 'raises ServerError on a timeout the client has wrapped' do
      error = InfluxDB2::InfluxError.from_error(Timeout::Error.new('too slow'))

      allow(write_api_double).to receive(:write).and_raise(error)

      expect { described_class.write(lines, **params) }.to raise_error(
        InfluxWriter::ServerError,
        /Network error.*too slow/,
      )
    end

    # Nothing here says that the lines are wrong, so they stay queued instead
    # of being dropped.
    it 'raises ServerError on an InfluxError without status and cause' do
      error =
        InfluxDB2::InfluxError.new(
          message: 'connection reset',
          code: nil,
          reference: nil,
          retry_after: nil,
        )

      allow(write_api_double).to receive(:write).and_raise(error)

      expect { described_class.write(lines, **params) }.to raise_error(
        InfluxWriter::ServerError,
        /Unknown error.*connection reset/,
      )
    end

    it 're-raises network errors like SocketError' do
      allow(write_api_double).to receive(:write).and_raise(
        SocketError.new('host unreachable'),
      )

      expect { described_class.write(lines, **params) }.to raise_error(
        SocketError,
        /host unreachable/,
      )
    end
  end
end
