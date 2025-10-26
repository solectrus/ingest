require "../spec_helper"

describe OutboxWorker do
  describe ".run_once" do
    it "returns zero when no outgoings exist" do
      processed = OutboxWorker.run_once
      processed.should eq(0)
    end

    context "when all writes succeed" do
      it "writes batches to InfluxDB and deletes all outgoings" do
        target = create_target(
          influx_token: "test-token",
          bucket: "test-bucket",
          org: "test-org"
        )

        # Create 3 outgoings: 2 with timestamp=1000, 1 with timestamp=2000
        Outgoing.new(
          target_id: target.id.not_nil!,
          line_protocol: "measurement1 field=1i 1000"
        ).save!

        Outgoing.new(
          target_id: target.id.not_nil!,
          line_protocol: "measurement2 field=2i 1000"
        ).save!

        Outgoing.new(
          target_id: target.id.not_nil!,
          line_protocol: "measurement3 field=3i 2000"
        ).save!

        initial_count = Outgoing.count

        # Mock all HTTP requests to succeed (match any query params)
        WebMock.stub(:post, %r{http://localhost:8086/api/v2/write\?.*})
          .to_return(status: 204)

        processed = OutboxWorker.run_once

        processed.should eq(3)
        Outgoing.count.should eq(0)
        (initial_count - Outgoing.count).should eq(3)
      end
    end

    context "when a permanent write fails (ClientError)" do
      it "deletes permanently failed and successfully written outgoings" do
        target = create_target(
          influx_token: "test-token",
          bucket: "test-bucket",
          org: "test-org"
        )

        # Create 3 outgoings
        Outgoing.new(
          target_id: target.id.not_nil!,
          line_protocol: "measurement1 field=1i 1000"
        ).save!

        Outgoing.new(
          target_id: target.id.not_nil!,
          line_protocol: "measurement2 field=2i 1000"
        ).save!

        Outgoing.new(
          target_id: target.id.not_nil!,
          line_protocol: "measurement3 field=3i 2000"
        ).save!

        initial_count = Outgoing.count

        # Mock: timestamp=1000 batch fails with ClientError (400)
        WebMock.stub(:post, %r{http://localhost:8086/api/v2/write\?.*})
          .with(body: "measurement1 field=1i 1000\nmeasurement2 field=2i 1000")
          .to_return(status: 400, body: "invalid token")

        # Mock: timestamp=2000 batch succeeds
        WebMock.stub(:post, %r{http://localhost:8086/api/v2/write\?.*})
          .with(body: "measurement3 field=3i 2000")
          .to_return(status: 204)

        processed = OutboxWorker.run_once

        # Only timestamp=2000 counts as processed
        processed.should eq(1)

        # All outgoings deleted (permanent failure + success)
        Outgoing.count.should eq(0)
        (initial_count - Outgoing.count).should eq(3)
      end
    end

    context "when a temporary write fails (ServerError)" do
      it "keeps outgoings that failed temporarily and deletes successful ones" do
        target = create_target(
          influx_token: "test-token",
          bucket: "test-bucket",
          org: "test-org"
        )

        # Create 3 outgoings
        out1 = Outgoing.new(
          target_id: target.id.not_nil!,
          line_protocol: "measurement1 field=1i 1000"
        )
        out1.save!
        id1 = out1.id

        out2 = Outgoing.new(
          target_id: target.id.not_nil!,
          line_protocol: "measurement2 field=2i 1000"
        )
        out2.save!
        id2 = out2.id

        out3 = Outgoing.new(
          target_id: target.id.not_nil!,
          line_protocol: "measurement3 field=3i 2000"
        )
        out3.save!

        initial_count = Outgoing.count

        # Mock: timestamp=1000 batch fails with ServerError (503)
        WebMock.stub(:post, %r{http://localhost:8086/api/v2/write\?.*})
          .with(body: "measurement1 field=1i 1000\nmeasurement2 field=2i 1000")
          .to_return(status: 503, body: "Influx down")

        # Mock: timestamp=2000 batch succeeds
        WebMock.stub(:post, %r{http://localhost:8086/api/v2/write\?.*})
          .with(body: "measurement3 field=3i 2000")
          .to_return(status: 204)

        processed = OutboxWorker.run_once

        # Only timestamp=2000 counts as processed
        processed.should eq(1)

        # Only successful outgoing deleted, failed ones kept
        Outgoing.count.should eq(2)
        (initial_count - Outgoing.count).should eq(1)

        # Check that the right outgoings remain
        remaining_ids = Database.pool.query_all(
          "SELECT id FROM outgoings ORDER BY id",
          as: Int64
        )
        remaining_ids.should contain(id1)
        remaining_ids.should contain(id2)
      end
    end
  end
end
