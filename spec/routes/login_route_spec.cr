require "../spec_helper"

describe "Login Routes" do
  describe "GET /login" do
    it "returns 200 OK with login form" do
      get "/login"
      response.status_code.should eq(200)
      response.body.should contain("password")
    end
  end

  describe "POST /login" do
    context "with correct password" do
      before_each { EnvHelper.setup({"STATS_PASSWORD" => "secret123"}) }
      after_each { EnvHelper.teardown }

      it "sets cookie and redirects to root" do
        headers = HTTP::Headers.new
        headers["Content-Type"] = "application/x-www-form-urlencoded"
        post "/login", headers: headers, body: "password=secret123"

        response.status_code.should eq(302)
        response.headers["Location"].should eq("/")

        cookie = response.cookies.find { |c| c.name == "password" }
        cookie.should_not be_nil
        cookie.not_nil!.value.should eq("secret123")
      end

      it "redirects to return_to URL if set" do
        headers = HTTP::Headers.new
        headers["Content-Type"] = "application/x-www-form-urlencoded"
        headers["Cookie"] = "return_to=/stats"

        post "/login", headers: headers, body: "password=secret123"

        response.status_code.should eq(302)
        response.headers["Location"].should eq("/stats")
      end
    end

    context "with incorrect password" do
      before_each { EnvHelper.setup({"STATS_PASSWORD" => "secret123"}) }
      after_each { EnvHelper.teardown }

      it "shows error message" do
        headers = HTTP::Headers.new
        headers["Content-Type"] = "application/x-www-form-urlencoded"
        post "/login", headers: headers, body: "password=wrong"

        response.status_code.should eq(200)
        response.body.should contain("Invalid, try again")
      end
    end

    context "without password set" do
      before_each { EnvHelper.setup({"STATS_PASSWORD" => nil}) }
      after_each { EnvHelper.teardown }

      it "denies login" do
        headers = HTTP::Headers.new
        headers["Content-Type"] = "application/x-www-form-urlencoded"
        post "/login", headers: headers, body: "password=anything"

        response.status_code.should eq(200)
        response.body.should contain("Invalid, try again")
      end
    end
  end
end
