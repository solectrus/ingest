require "spec"
require "spec-kemal"
require "webmock"

# Load support files
require "./support/**"

# Set test environment
ENV["KEMAL_ENV"] = "test"
ENV["APP_ENV"] = "test"

# Load application
require "../src/ingest"

# Helper to reset database between tests
def reset_database!
  Incoming.delete_all
  Outgoing.delete_all
  Target.delete_all

  # Reset caches
  SensorValueCache.instance.reset!
  Stats.reset!
end

# Run before each spec
Spec.before_each do
  reset_database!
  WebMock.reset
end

# Helper to create a target
def create_target(
  bucket : String = "test-bucket",
  org : String = "test-org",
  influx_token : String = "test-token",
  precision : String = "ns",
) : Target
  target = Target.new
  target.bucket = bucket
  target.org = org
  target.influx_token = influx_token
  target.precision = precision
  target.save!
  target
end

# Helper to create an incoming
def create_incoming(
  target : Target,
  measurement : String = "test",
  field : String = "value",
  timestamp : Int64? = nil,
  value : Int64 | Float64 | String | Bool = 42,
  created_at : Time? = nil,
) : Incoming
  incoming = Incoming.new
  incoming.target_id = target.id.not_nil!
  incoming.measurement = measurement
  incoming.field = field
  incoming.timestamp = timestamp || Time.utc.to_unix * 1_000_000_000
  incoming.value = value
  incoming.save!

  # Update created_at if specified
  if created_at
    Incoming.update(
      incoming.id.not_nil!,
      created_at: created_at.to_s("%Y-%m-%d %H:%M:%S.%6N")
    )
  end

  incoming
end

# Helper to create an outgoing
def create_outgoing(
  target : Target,
  line_protocol : String = "test value=42i 1234567890",
) : Outgoing
  outgoing = Outgoing.new
  outgoing.target_id = target.id.not_nil!
  outgoing.line_protocol = line_protocol
  outgoing.save!
  outgoing
end
