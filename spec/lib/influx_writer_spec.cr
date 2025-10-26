require "../spec_helper"

describe InfluxWriter do
  describe ".write" do
    it "sends data to InfluxDB" do
      WebMock.stub(:post, "http://localhost:8086/api/v2/write?bucket=test-bucket&org=test-org&precision=ns")
        .to_return(status: 204)

      InfluxWriter.write(
        lines: "measurement field=42i 1234567890",
        influx_token: "test-token",
        bucket: "test-bucket",
        org: "test-org",
        precision: "ns"
      )

      # If we get here without exception, the test passes
    end

    it "sends array of lines to InfluxDB" do
      WebMock.stub(:post, "http://localhost:8086/api/v2/write?bucket=test-bucket&org=test-org&precision=ns")
        .to_return(status: 204)

      InfluxWriter.write(
        lines: ["measurement field=42i 1234567890", "measurement field=43i 1234567891"],
        influx_token: "test-token",
        bucket: "test-bucket",
        org: "test-org",
        precision: "ns"
      )
    end

    it "raises ClientError on 4xx response" do
      WebMock.stub(:post, "http://localhost:8086/api/v2/write?bucket=test-bucket&org=test-org&precision=ns")
        .to_return(status: 400, body: "Bad request")

      expect_raises(InfluxWriter::ClientError, /Client error \(400\)/) do
        InfluxWriter.write(
          lines: "measurement field=42i",
          influx_token: "test-token",
          bucket: "test-bucket",
          org: "test-org",
          precision: "ns"
        )
      end
    end

    it "raises ServerError on 5xx response" do
      WebMock.stub(:post, "http://localhost:8086/api/v2/write?bucket=test-bucket&org=test-org&precision=ns")
        .to_return(status: 500, body: "Internal server error")

      expect_raises(InfluxWriter::ServerError, /Server error \(500\)/) do
        InfluxWriter.write(
          lines: "measurement field=42i",
          influx_token: "test-token",
          bucket: "test-bucket",
          org: "test-org",
          precision: "ns"
        )
      end
    end

    it "makes HTTP POST request" do
      stub = WebMock.stub(:post, "http://localhost:8086/api/v2/write?bucket=test-bucket&org=test-org&precision=ns")
        .to_return(status: 204)

      InfluxWriter.write(
        lines: "measurement field=42i",
        influx_token: "test-token",
        bucket: "test-bucket",
        org: "test-org",
        precision: "ns"
      )

      stub.calls.should eq(1)
    end
  end
end
