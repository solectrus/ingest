require "../spec_helper"

describe EncodingHelper do
  describe ".clean_utf8" do
    it "returns a valid UTF-8 string unchanged" do
      input = "Hello ☀️"
      output = EncodingHelper.clean_utf8(input)
      output.should eq("Hello ☀️")
      output.valid_encoding?.should be_true
    end

    it "handles UTF-8 characters correctly" do
      input = "Grüße"
      output = EncodingHelper.clean_utf8(input)
      output.should eq("Grüße")
      output.valid_encoding?.should be_true
    end

    it "does not modify the original string" do
      original = "test"
      original_value = original.dup
      EncodingHelper.clean_utf8(original)
      original.should eq(original_value)
    end
  end
end
