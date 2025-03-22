require 'spec_helper'

describe App do
  let(:app) { described_class.new }

  let(:params) { 'bucket=test-bucket&org=test-org' }
  let(:line_protocol) { 'test,location=spec value=1 1234567890000000000' }

  it 'responds with 204 on successful write' do
    allow(InfluxWriter).to receive(:forward_influx_line).and_return(true)

    post "/api/v2/write?#{params}",
         line_protocol,
         {
           'HTTP_AUTHORIZATION' => 'Token test-token',
           'CONTENT_TYPE' => 'text/plain',
         }

    expect(last_response.status).to eq 204
  end

  it 'buffers on Influx failure' do
    allow(InfluxWriter).to receive(:forward_influx_line).and_raise(Errno::ECONNREFUSED.new)
    allow(Buffer).to receive(:add)

    post "/api/v2/write?#{params}",
         line_protocol,
         {
           'HTTP_AUTHORIZATION' => 'Token test-token',
           'CONTENT_TYPE' => 'text/plain',
         }

    expect(Buffer).to have_received(:add)
    expect(last_response.status).to eq 202
  end

  it 'returns 400 on InfluxDB parse error' do
    allow(InfluxWriter).to receive(:forward_influx_line).and_raise(
      InfluxDB2::InfluxError.new(
        message: 'unable to parse line protocol',
        code: 'invalid',
        reference: '',
        retry_after: 0,
      ),
    )

    post "/api/v2/write?#{params}", line_protocol, {
      'HTTP_AUTHORIZATION' => 'Token test-token',
      'CONTENT_TYPE' => 'text/plain',
    }

    expect(last_response.status).to eq 400
    expect(last_response.body).to include('unable to parse line protocol')
  end

  it 'healthcheck works' do
    get '/health'
    expect(last_response.status).to eq 200
    expect(last_response.body).to eq 'OK'
  end
end
