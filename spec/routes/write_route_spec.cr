require "../spec_helper"

describe "Write Route" do
  describe "POST /api/v2/write" do
    it "returns 401 without authorization header" do
      post "/api/v2/write"

      response.status_code.should eq(401)
      response.body.should contain("Missing token")
    end

    it "returns 401 with invalid authorization header" do
      headers = HTTP::Headers.new
      headers["Authorization"] = "Invalid"

      post "/api/v2/write", headers: headers

      response.status_code.should eq(401)
      response.body.should contain("Missing token")
    end

    it "returns 400 without bucket parameter" do
      headers = HTTP::Headers.new
      headers["Authorization"] = "Token test-token"

      post "/api/v2/write", headers: headers

      response.status_code.should eq(400)
      response.body.should contain("Missing bucket")
    end

    it "returns 400 without org parameter" do
      headers = HTTP::Headers.new
      headers["Authorization"] = "Token test-token"

      post "/api/v2/write?bucket=test-bucket", headers: headers

      response.status_code.should eq(400)
      response.body.should contain("Missing org")
    end

    it "returns 204 with empty body" do
      headers = HTTP::Headers.new
      headers["Authorization"] = "Token test-token"

      post "/api/v2/write?bucket=test-bucket&org=test-org", headers: headers, body: ""

      response.status_code.should eq(204)
    end

    it "sets response headers" do
      headers = HTTP::Headers.new
      headers["Authorization"] = "Token test-token"

      post "/api/v2/write?bucket=test-bucket&org=test-org", headers: headers, body: ""

      response.headers["X-Ingest-Version"]?.should_not be_nil
      response.headers["Date"]?.should_not be_nil
    end

    context "with valid line protocol" do
      it "returns 204" do
        headers = HTTP::Headers.new
        headers["Authorization"] = "Token test-token"
        headers["Content-Type"] = "text/plain"

        body = "measurement,tag=value field=42i 1234567890"

        post "/api/v2/write?bucket=test-bucket&org=test-org&precision=ns",
          headers: headers,
          body: body

        response.status_code.should eq(204)
      end

      it "handles UTF-8 characters" do
        headers = HTTP::Headers.new
        headers["Authorization"] = "Token test-token"
        headers["Content-Type"] = "text/plain"

        # Line with UTF-8 characters (degree symbol, bullet)
        body = "FOO system_status=\"37° • Charging\" 1743943068000000000"

        post "/api/v2/write?bucket=test-bucket&org=test-org&precision=ns",
          headers: headers,
          body: body

        response.status_code.should eq(204)
      end
    end

    context "with invalid line protocol" do
      it "returns 400 with error message" do
        headers = HTTP::Headers.new
        headers["Authorization"] = "Token test-token"
        headers["Content-Type"] = "text/plain"

        # This will fail because it doesn't match the LINE_PROTOCOL_REGEX
        body = "   "

        post "/api/v2/write?bucket=test-bucket&org=test-org",
          headers: headers,
          body: body

        # Empty/whitespace body returns 204, so let's use a truly invalid format
        # Line protocol must have at least measurement and field
        body = "measurement"

        post "/api/v2/write?bucket=test-bucket&org=test-org",
          headers: headers,
          body: body

        response.status_code.should eq(400)
        response.body.should contain("error")
      end
    end
  end
end
