require "../spec_helper"

describe Outgoing do
  describe "#save!" do
    it "saves outgoing to database" do
      target = create_target

      outgoing = Outgoing.new
      outgoing.target_id = target.id.not_nil!
      outgoing.line_protocol = "measurement field=42i 1234567890"

      outgoing.save!

      outgoing.id.should_not be_nil
    end
  end
end
