describe HealthRoute do
  def app
    HealthRoute.new
  end

  describe 'GET /health' do
    it 'returns 200 with green HTML' do
      get '/health'

      expect(last_response.status).to eq(200)
      expect(last_response.content_type).to include('text/html')
      expect(last_response.body).to include('background-color: green')
    end
  end

  describe 'HEAD /health' do
    it 'returns 200 with empty body' do
      head '/health'

      expect(last_response.status).to eq(200)
      expect(last_response.body).to be_empty
    end
  end

  describe 'GET /ping' do
    it 'returns 204' do
      get '/ping'

      expect(last_response.status).to eq(204)
    end
  end

  describe 'HEAD /ping' do
    it 'returns 204' do
      head '/ping'

      expect(last_response.status).to eq(204)
    end
  end
end
