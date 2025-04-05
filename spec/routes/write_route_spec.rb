describe WriteRoute do
  def app
    WriteRoute.new
  end

  let(:headers) do
    {
      'CONTENT_TYPE' => 'application/json',
      'HTTP_AUTHORIZATION' => 'Token test-token',
    }
  end

  let(:params) { 'bucket=test-bucket&org=test-org' }
  let(:line) { "SENEC inverter_power=500 #{Time.now.to_i * 1_000_000_000}" }

  def post_write(query: params, body: line, custom_headers: headers)
    post "/api/v2/write?#{query}", body, custom_headers
  end

  def expect_default_header
    expect(last_response.headers).to have_key('X-Ingest-Version')
    expect(last_response.headers).to have_key('Date')
  end

  def expect_status(status)
    expect(last_response.status).to eq(status)
  end

  def expect_body(content)
    if content
      expect(last_response.body).to include(content)
    else
      expect(last_response.body).to be_empty
    end
  end

  describe 'POST /api/v2/write' do
    context 'with valid request' do
      it 'stores data and returns 204' do
        expect { post_write }.to change(Incoming, :count).by(1).and(
          change(Outgoing, :count).by(1),
        )

        expect_status 204
        expect_default_header
      end
    end

    context 'when token is missing' do
      it 'returns 401' do
        post_write(custom_headers: headers.except('HTTP_AUTHORIZATION'))

        expect_status 401
        expect_default_header
        expect_body 'Missing token'
      end
    end

    context 'when bucket is missing' do
      it 'returns 400' do
        post_write(query: 'org=test-org')

        expect_status 400
        expect_body 'Missing bucket'
        expect_default_header
      end
    end

    context 'when org is missing' do
      it 'returns 400' do
        post_write(query: 'bucket=test-bucket')

        expect_status 400
        expect_body 'Missing org'
        expect_default_header
      end
    end

    context 'when request body is blank' do
      it 'returns 204 with empty body' do
        post_write(body: '')

        expect_status 204
        expect_body nil
        expect_default_header
      end
    end

    context 'when line protocol is invalid' do
      it 'returns 400 with error message' do
        post_write(body: 'invalid_line')

        expect_status 400
        expect_body 'Invalid line protocol'
        expect_default_header
      end
    end

    context 'when unknown error occurs' do
      before do
        processor = instance_double(Processor)
        allow(processor).to receive(:run).and_raise(StandardError, 'Boom!')
        allow(Processor).to receive(:new).and_return(processor)
      end

      it 'returns 500 with error message' do
        post_write

        expect_status 500
        expect_body 'Boom!'
        expect_default_header
      end
    end
  end
end
