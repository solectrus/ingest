require "../spec_helper"

describe "Stats Route" do
  describe "GET /" do
    context "without password protection" do
      before_each { EnvHelper.setup({"STATS_PASSWORD" => nil}) }
      after_each { EnvHelper.teardown }

      it "shows stats page" do
        get "/"

        response.status_code.should eq(200)
        response.body.should contain("SOLECTRUS")
      end
    end

    context "with password protection" do
      before_each { EnvHelper.setup({"STATS_PASSWORD" => "secret123"}) }
      after_each { EnvHelper.teardown }

      it "redirects to login without cookie" do
        get "/"

        response.status_code.should eq(302)
        response.headers["Location"].should eq("/login")

        return_to_cookie = response.cookies.find { |c| c.name == "return_to" }
        return_to_cookie.should_not be_nil
        return_to_cookie.not_nil!.value.should eq("/")
      end

      it "shows stats with correct cookie" do
        headers = HTTP::Headers.new
        headers["Cookie"] = "password=secret123"

        get "/", headers: headers

        response.status_code.should eq(200)
        response.body.should contain("SOLECTRUS")
      end

      it "redirects to login with incorrect cookie" do
        headers = HTTP::Headers.new
        headers["Cookie"] = "password=wrong"

        get "/", headers: headers

        response.status_code.should eq(302)
        response.headers["Location"].should eq("/login")
      end
    end
  end
end
