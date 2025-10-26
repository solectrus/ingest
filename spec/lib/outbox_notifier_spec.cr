require "../spec_helper"

describe OutboxNotifier do
  describe ".notify!" do
    it "notifies without blocking" do
      # Should not raise error
      OutboxNotifier.notify!
    end

    it "can be called multiple times" do
      OutboxNotifier.notify!
      OutboxNotifier.notify!
      OutboxNotifier.notify!
    end
  end

  describe ".wait" do
    it "can call wait" do
      spawn do
        sleep(1.millisecond)
        OutboxNotifier.notify!
      end

      # Should not raise error
      spawn do
        OutboxNotifier.wait
      end

      sleep(10.milliseconds) # Give it time to complete
    end
  end
end
