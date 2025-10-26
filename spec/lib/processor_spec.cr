require "../spec_helper"

describe Processor do
  describe "#run" do
    it "processes line protocol and stores in database" do
      processor = Processor.new(
        influx_token: "test-token",
        bucket: "test-bucket",
        org: "test-org",
        precision: "ns"
      )

      lines = ["measurement field1=42i,field2=3.14 1234567890"]
      processor.run(lines)

      # Verify target was created
      target = Target.find_by(
        influx_token: "test-token",
        bucket: "test-bucket",
        org: "test-org",
        precision: "ns"
      )
      target.should_not be_nil

      # Verify incoming records were created
      db = DB.open("sqlite3://#{Database.file}")
      count = db.query_one("SELECT COUNT(*) FROM incomings WHERE target_id = ?", target.not_nil!.id, as: Int64)
      count.should eq(2) # Two fields

      # Verify outgoing record was created
      outgoing_count = db.query_one("SELECT COUNT(*) FROM outgoings WHERE target_id = ?", target.not_nil!.id, as: Int64)
      outgoing_count.should eq(1)

      db.close
    end

    it "handles integer values" do
      processor = Processor.new(
        influx_token: "test-token",
        bucket: "test-bucket",
        org: "test-org",
        precision: "ns"
      )

      lines = ["measurement int_field=100i 1234567890"]
      processor.run(lines)

      db = DB.open("sqlite3://#{Database.file}")
      value = db.query_one(
        "SELECT value_int FROM incomings WHERE field = 'int_field' LIMIT 1",
        as: Int64?
      )
      db.close

      value.should eq(100)
    end

    it "handles float values" do
      processor = Processor.new(
        influx_token: "test-token",
        bucket: "test-bucket",
        org: "test-org",
        precision: "ns"
      )

      lines = ["measurement float_field=3.14 1234567890"]
      processor.run(lines)

      db = DB.open("sqlite3://#{Database.file}")
      value = db.query_one(
        "SELECT value_float FROM incomings WHERE field = 'float_field' LIMIT 1",
        as: Float64?
      )
      db.close

      value.should eq(3.14)
    end

    it "handles string values" do
      processor = Processor.new(
        influx_token: "test-token",
        bucket: "test-bucket",
        org: "test-org",
        precision: "ns"
      )

      lines = ["measurement string_field=\"hello\" 1234567890"]
      processor.run(lines)

      db = DB.open("sqlite3://#{Database.file}")
      value = db.query_one(
        "SELECT value_string FROM incomings WHERE field = 'string_field' LIMIT 1",
        as: String?
      )
      db.close

      value.should eq("hello")
    end

    it "handles boolean values" do
      processor = Processor.new(
        influx_token: "test-token",
        bucket: "test-bucket",
        org: "test-org",
        precision: "ns"
      )

      lines = ["measurement bool_field=true 1234567890"]
      processor.run(lines)

      db = DB.open("sqlite3://#{Database.file}")
      value = db.query_one(
        "SELECT value_bool FROM incomings WHERE field = 'bool_field' LIMIT 1",
        as: Int32?
      )
      db.close

      value.should eq(1)
    end

    it "caches numeric values" do
      processor = Processor.new(
        influx_token: "test-token",
        bucket: "test-bucket",
        org: "test-org",
        precision: "ns"
      )

      lines = ["SENEC inverter_power=1000i 1234567890000000000"]
      processor.run(lines)

      # Verify value was cached
      cached = SensorValueCache.instance.read(
        measurement: "SENEC",
        field: "inverter_power",
        max_timestamp: 1234567890000000000_i64
      )

      cached.should_not be_nil
      cached.not_nil!.value.should eq(1000.0)
    end

    it "reuses existing target" do
      processor1 = Processor.new(
        influx_token: "same-token",
        bucket: "same-bucket",
        org: "same-org",
        precision: "ns"
      )

      processor2 = Processor.new(
        influx_token: "same-token",
        bucket: "same-bucket",
        org: "same-org",
        precision: "ns"
      )

      processor1.run(["measurement field=1i 1234567890"])
      processor2.run(["measurement field=2i 1234567891"])

      # Should only have one target
      db = DB.open("sqlite3://#{Database.file}")
      count = db.query_one("SELECT COUNT(*) FROM targets", as: Int64)
      db.close

      count.should eq(1)
    end

    it "handles multiple lines" do
      processor = Processor.new(
        influx_token: "test-token",
        bucket: "test-bucket",
        org: "test-org",
        precision: "ns"
      )

      lines = [
        "measurement1 field=1i 1234567890",
        "measurement2 field=2i 1234567891",
        "measurement3 field=3i 1234567892",
      ]

      processor.run(lines)

      db = DB.open("sqlite3://#{Database.file}")
      count = db.query_one(
        "SELECT COUNT(*) FROM incomings WHERE target_id = (SELECT id FROM targets LIMIT 1)",
        as: Int64
      )
      db.close

      count.should eq(3)
    end

    it "handles tags" do
      processor = Processor.new(
        influx_token: "test-token",
        bucket: "test-bucket",
        org: "test-org",
        precision: "ns"
      )

      lines = ["measurement,host=server1,region=eu field=42i 1234567890"]
      processor.run(lines)

      db = DB.open("sqlite3://#{Database.file}")
      tags_json = db.query_one("SELECT tags FROM incomings LIMIT 1", as: String)
      db.close

      tags_json.should contain("host")
      tags_json.should contain("server1")
    end

    it "filters out house_power field when enqueuing outgoing" do
      processor = Processor.new(
        influx_token: "test-token",
        bucket: "test-bucket",
        org: "test-org",
        precision: "ns"
      )

      lines = ["SENEC house_power=300i,grid_power_plus=500i 1000000000"]
      processor.run(lines)

      outgoing = Outgoing.last
      outgoing.should_not be_nil
      outgoing.not_nil!.line_protocol.should eq("SENEC grid_power_plus=500i 1000000000")
    end

    it "skips enqueue if only house_power is present" do
      processor = Processor.new(
        influx_token: "test-token",
        bucket: "test-bucket",
        org: "test-org",
        precision: "ns"
      )

      initial_count = Outgoing.count
      lines = ["SENEC house_power=300i 1000000000"]
      processor.run(lines)
      new_count = Outgoing.count

      (new_count - initial_count).should eq(0)
    end
  end
end
