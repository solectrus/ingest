get "/health" do |env|
  if env.request.method == "HEAD"
    env.response.status_code = 200
    next
  end

  env.response.content_type = "application/json"
  {
    name:    "ingest",
    message: "ready for writes",
    status:  "pass",
    checks:  [] of String,
    version: BuildInfo.version,
    commit:  BuildInfo.revision_short,
  }.to_json
end

get "/ping" do |env|
  env.response.status_code = 204
end
