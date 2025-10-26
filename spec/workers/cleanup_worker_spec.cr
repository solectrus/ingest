require "../spec_helper"

describe CleanupWorker do
  target = nil.as(Target?)
  old_entry = nil.as(Incoming?)
  recent_entry = nil.as(Incoming?)

  before_each do
    target = create_target(
      influx_token: "foo",
      bucket: "test",
      org: "test"
    )

    # Create old entry (37 hours ago - older than 36 hours retention)
    old_entry = create_incoming(
      target: target.not_nil!,
      measurement: "SENEC",
      field: "test",
      value: 42_i64,
      created_at: Time.utc - 37.hours
    )

    # Create recent entry (20 hours ago - within 36 hour retention period)
    recent_entry = create_incoming(
      target: target.not_nil!,
      measurement: "SENEC",
      field: "test",
      value: 42_i64,
      created_at: Time.utc - 20.hours
    )
  end

  describe ".run" do
    before_each do
      CleanupWorker.run
    end

    it "deletes old entries" do
      # Check if old entry was deleted (should not exist)
      count = Database.pool.query_one(
        "SELECT COUNT(*) FROM incomings WHERE id = ?",
        old_entry.not_nil!.id.not_nil!,
        as: Int64
      )
      count.should eq(0)
    end

    it "does not delete recent entries" do
      # Check if recent entry still exists
      count = Database.pool.query_one(
        "SELECT COUNT(*) FROM incomings WHERE id = ?",
        recent_entry.not_nil!.id.not_nil!,
        as: Int64
      )
      count.should eq(1)
    end
  end
end
