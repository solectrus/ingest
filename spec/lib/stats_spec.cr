require "../spec_helper"

describe Stats do
  describe ".inc" do
    it "increments counter" do
      Stats.reset!

      Stats.inc(:test)
      Stats.inc(:test)

      Stats.counter(:test).should eq(2)
    end
  end

  describe ".add" do
    it "adds to sum" do
      Stats.reset!

      Stats.add(:test, 10.5)
      Stats.add(:test, 20.3)

      Stats.sum(:test).should be_close(30.8, 0.01)
    end
  end

  describe ".counter" do
    it "returns 0 for non-existent counter" do
      Stats.reset!

      Stats.counter(:nonexistent).should eq(0)
    end
  end

  describe ".counters_by" do
    it "returns counters matching prefix" do
      Stats.reset!

      Stats.inc(:http_response_200)
      Stats.inc(:http_response_404)
      Stats.inc(:other_counter)

      counters = Stats.counters_by(:http_response)

      counters.size.should eq(2)
      counters[:http_response_200].should eq(1)
      counters[:http_response_404].should eq(1)
    end
  end

  describe ".reset!" do
    it "resets all stats" do
      Stats.inc(:test)
      Stats.add(:test_sum, 10.0)

      Stats.reset!

      Stats.counter(:test).should eq(0)
      Stats.sum(:test_sum).should eq(0.0)
    end

    it "resets specific key" do
      Stats.inc(:test1)
      Stats.inc(:test2)

      Stats.reset!(:test1)

      Stats.counter(:test1).should eq(0)
      Stats.counter(:test2).should eq(1)
    end
  end
end
