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

  describe 'POST /api/v2/write' do
    context 'with valid request' do
      it 'stores data and returns 204' do
        expect do
          ###
          post("/api/v2/write?#{params}", line, headers)
        end.to change(Incoming, :count).by(1).and change(Outgoing, :count).by(1)

        expect(last_response.status).to eq(204)
      end
    end

    context 'when token is missing' do
      it 'returns 401' do
        post "/api/v2/write?#{params}",
             line,
             headers.except('HTTP_AUTHORIZATION')

        expect(last_response.status).to eq(401)
        expect(last_response.body).to include('Missing token')
      end
    end

    context 'when bucket is missing' do
      it 'returns 400' do
        post '/api/v2/write?org=test-org', line, headers

        expect(last_response.status).to eq(400)
        expect(last_response.body).to include('Missing bucket')
      end
    end

    context 'when org is missing' do
      it 'returns 400' do
        post '/api/v2/write?bucket=test-bucket', line, headers

        expect(last_response.status).to eq(400)
        expect(last_response.body).to include('Missing org')
      end
    end

    context 'when request body is blank' do
      it 'returns 204' do
        post "/api/v2/write?#{params}", '', headers

        expect(last_response.status).to eq(204)
        expect(last_response.body).to be_empty
      end
    end

    context 'when line protocol is invalid' do
      it 'returns 400 with error message' do
        post "/api/v2/write?#{params}", 'invalid_line', headers

        expect(last_response.status).to eq(400)
        expect(last_response.body).to include('Invalid line protocol')
      end
    end

    context 'when unknown error occurs' do
      before do
        processor = instance_double(Processor)
        allow(processor).to receive(:run).and_raise(StandardError, 'Boom!')
        allow(Processor).to receive(:new).and_return(processor)
      end

      it 'returns 500 with error message' do
        post "/api/v2/write?#{params}", line, headers

        expect(last_response.status).to eq(500)
        expect(last_response.body).to include('Boom!')
      end
    end
  end
end
