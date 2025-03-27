describe UpRoute do
  def app
    UpRoute.new
  end

  describe 'GET /up' do
    it 'returns 200 with green HTML' do
      get '/up'

      expect(last_response.status).to eq(200)
      expect(last_response.content_type).to include('text/html')
      expect(last_response.body).to include('background-color: green')
    end
  end

  describe 'HEAD /up' do
    it 'returns 200 with empty body' do
      head '/up'

      expect(last_response.status).to eq(200)
      expect(last_response.body).to be_empty
    end
  end
end
