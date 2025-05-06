class HealthRoute < BaseRoute
  get '/health' do
    if request.head?
      status 200
      body nil
    else
      content_type :json
      {
        name: 'ingest',
        message: 'ready for writes',
        status: 'pass',
        checks: [],
        version: BuildInfo.version,
        commit: BuildInfo.revision_short,
      }.to_json
    end
  end

  get '/ping' do
    status 204
  end
end
