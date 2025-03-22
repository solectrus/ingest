require 'spec_helper'

describe App do
  let(:app) { App.new }

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
    allow(InfluxWriter).to receive(:forward_influx_line).and_raise(
      'influx down',
    )
    expect(Buffer).to receive(:add)

    post "/api/v2/write?#{params}",
         line_protocol,
         {
           'HTTP_AUTHORIZATION' => 'Token test-token',
           'CONTENT_TYPE' => 'text/plain',
         }

    expect(last_response.status).to eq 202
  end

  it 'healthcheck works' do
    get '/health'
    expect(last_response.status).to eq 200
    expect(last_response.body).to eq 'OK'
  end
end
