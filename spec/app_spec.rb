describe App do
  let(:app) { described_class.new }

  let(:params) { 'bucket=test-bucket&org=test-org' }
  let(:line_protocol) { 'SENEC inverter_power=500 1234567890000000000' }

  it 'responds with 204 on successful write' do
    allow_any_instance_of(LineProcessor).to receive(:process).and_return(true) # rubocop:disable RSpec/AnyInstance

    post "/api/v2/write?#{params}",
         line_protocol,
         {
           'HTTP_AUTHORIZATION' => 'Token test-token',
           'CONTENT_TYPE' => 'text/plain',
         }

    expect(last_response.status).to eq 204
  end

  it 'returns 401 if token is missing' do
    post "/api/v2/write?#{params}",
         line_protocol,
         { 'CONTENT_TYPE' => 'text/plain' }
    expect(last_response.status).to eq 401
  end

  it 'returns 400 if bucket is missing' do
    post '/api/v2/write?org=test-org',
         line_protocol,
         {
           'HTTP_AUTHORIZATION' => 'Token test-token',
           'CONTENT_TYPE' => 'text/plain',
         }

    expect(last_response.status).to eq 400
  end

  it 'returns 400 on invalid Line Protocol' do
    invalid_line = 'invalid_line_without_fields_or_timestamp'

    post "/api/v2/write?#{params}",
         invalid_line,
         {
           'HTTP_AUTHORIZATION' => 'Token test-token',
           'CONTENT_TYPE' => 'text/plain',
         }

    expect(last_response.status).to eq 400
  end

  it 'healthcheck returns OK' do
    get '/health'
    expect(last_response.status).to eq 200
    expect(last_response.body).to eq 'OK'
  end
end
