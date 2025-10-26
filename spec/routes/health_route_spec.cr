require "../spec_helper"

describe "Health Routes" do
  describe "GET /ping" do
    it "returns 204 No Content" do
      get "/ping"
      response.status_code.should eq(204)
    end
  end

  describe "HEAD /ping" do
    it "returns 204 with empty body" do
      head "/ping"
      response.status_code.should eq(204)
      response.body.should be_empty
    end
  end

  describe "GET /health" do
    it "returns 200 OK with JSON body" do
      get "/health"
      response.status_code.should eq(200)
      response.content_type.should eq("application/json")
      response.body.should contain("status")
    end
  end

  describe "HEAD /health" do
    it "returns 200 with empty body" do
      head "/health"
      response.status_code.should eq(200)
      response.body.should be_empty
    end
  end
end
