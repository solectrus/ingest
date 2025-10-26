get "/login" do |env|
  error_msg = ""
  render "src/views/login.ecr", "src/views/layout.ecr"
end

post "/login" do |env|
  password = ENV["STATS_PASSWORD"]?
  input_password = env.params.body["password"]?

  if input_password == password
    env.response.cookies << HTTP::Cookie.new(
      name: "password",
      value: password || "",
      path: "/",
      http_only: true,
      expires: Time.utc + 30.days
    )

    target = env.request.cookies["return_to"]?.try(&.value) || "/"
    env.response.cookies.delete("return_to")

    env.redirect target
  else
    error_msg = "Invalid, try again."
    render "src/views/login.ecr", "src/views/layout.ecr"
  end
end

# Helper for views
def build_info
  BuildInfo.to_s
end

def h(text : String) : String
  HTML.escape(text)
end
