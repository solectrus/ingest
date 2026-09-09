# InfluxDB answers Flux queries at /api/v2/query. Ingest keeps no data for
# reading, so it cannot answer one.
#
# 403 and not 404: a client that reads 404 sees a wrong URL and stops. A client
# that reads 403 sees a token without read permission, which is a state
# InfluxDB itself produces, so it keeps its own defaults and goes on writing.
# The SOLECTRUS integration for Home Assistant asks for the field types of a
# bucket before its first write, and 403 is what lets it start against Ingest.
class QueryRoute < BaseRoute
  get('/api/v2/query') { forbidden }
  post('/api/v2/query') { forbidden }

  private

  def forbidden
    content_type 'application/json'

    halt 403,
         {
           code: 'forbidden',
           message: 'Ingest accepts writes only and cannot answer queries',
         }.to_json
  end
end
