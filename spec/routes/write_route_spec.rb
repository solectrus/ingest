describe WriteRoute do
  def app
    WriteRoute.new
  end

  let(:headers) do
    {
      'CONTENT_TYPE' => 'text/plain',
      'HTTP_AUTHORIZATION' => 'Token test-token',
    }
  end

  let(:params) { 'bucket=test-bucket&org=test-org' }
  let(:line_protocol) do
    "SENEC inverter_power=500 #{Time.now.to_i * 1_000_000_000}"
  end

  let(:processor) { instance_double(Processor, run: true) }

  describe 'POST /api/v2/write' do
    it 'returns 204 on success and stores data' do
      expect do
        post "/api/v2/write?#{params}", line_protocol, headers
      end.to change(Incoming, :count).by(1).and change(Outgoing, :count).by(1)

      expect(last_response.status).to eq(204)
    end

    it 'returns 401 if token is missing' do
      post "/api/v2/write?#{params}",
           line_protocol,
           { 'CONTENT_TYPE' => 'text/plain' }
      expect(last_response.status).to eq(401)
    end

    it 'returns 400 if bucket is missing' do
      post '/api/v2/write?org=test-org', line_protocol, headers
      expect(last_response.status).to eq(400)
    end

    it 'returns 400 if org is missing' do
      post '/api/v2/write?bucket=test-bucket', line_protocol, headers
      expect(last_response.status).to eq(400)
    end

    it 'returns 400 if line protocol is invalid' do
      post "/api/v2/write?#{params}", 'invalid_line', headers
      expect(last_response.status).to eq(400)
    end

    it 'returns 500 on unexpected error' do
      processor = instance_double(Processor)
      allow(processor).to receive(:run).and_raise(StandardError, 'boom')
      allow(Processor).to receive(:new).and_return(processor)

      post "/api/v2/write?#{params}", line_protocol, headers

      expect(last_response.status).to eq(500)
    end
  end
end
