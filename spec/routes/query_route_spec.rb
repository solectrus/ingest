describe QueryRoute do
  def app
    QueryRoute.new
  end

  shared_examples 'a refused query' do
    it 'returns 403 with JSON' do
      expect(last_response.status).to eq(403)
      expect(last_response.content_type).to include('application/json')
      expect(parsed_body).to include('code' => 'forbidden')
    end
  end

  describe 'POST /api/v2/query' do
    before { post '/api/v2/query', 'from(bucket: "test")' }

    it_behaves_like 'a refused query'
  end

  describe 'GET /api/v2/query' do
    before { get '/api/v2/query' }

    it_behaves_like 'a refused query'
  end
end
