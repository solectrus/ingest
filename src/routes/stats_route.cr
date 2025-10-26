include StatsHelpers

get "/" do |env|
  # Check authorization
  password = ENV["STATS_PASSWORD"]?

  if password && !password.empty?
    cookie_password = env.request.cookies["password"]?.try(&.value)

    unless cookie_password == password
      env.response.cookies << HTTP::Cookie.new(
        name: "return_to",
        value: env.request.path == "/login" ? "/" : env.request.path,
        path: "/",
        http_only: true
      )
      env.redirect "/login"
      next
    end
  end

  render "src/views/stats.ecr", "src/views/layout.ecr"
end

# Helper for views
def build_info
  BuildInfo.to_s
end

def h(text : String) : String
  HTML.escape(text)
end
