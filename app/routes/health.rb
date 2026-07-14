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

  # Answers like InfluxDB's /ping: the headers are what let a client confirm an
  # InfluxDB-compatible endpoint (a bare 204 proves nothing). Build says
  # "solectrus/ingest", not "OSS", so a client can still tell us apart.
  get '/ping' do
    headers 'X-Influxdb-Version' => BuildInfo.version,
            'X-Influxdb-Build' => 'solectrus/ingest'
    status 204
  end
end
