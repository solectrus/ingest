class TestRoute < BaseRoute
  post '/test-post' do
    content_type :json

    body = request.body.read

    begin
      data = JSON.parse(body)
      status 200
      { message: 'Received POST', data: data }.to_json
    rescue JSON::ParserError
      status 400
      { error: 'Invalid JSON' }.to_json
    end
  end
end
