require "../spec_helper"

describe Point do
  describe ".parse" do
    context "with timestamp" do
      it "parses name" do
        point = Point.parse("measurement,tag1=value1 field1=42i,field2=3.14 1234567890")

        point.name.should eq("measurement")
      end

      it "parses time" do
        point = Point.parse("measurement field1=42i 1234567890")

        point.time.should eq(1234567890)
      end

      it "parses fields" do
        point = Point.parse("measurement field1=42i,field2=3.14,field3=\"hello\",field4=true 1234567890")

        point.fields["field1"].should eq(42_i64)
        point.fields["field2"].should eq(3.14)
        point.fields["field3"].should eq("hello")
        point.fields["field4"].should eq(true)
      end

      it "parses tags" do
        point = Point.parse("measurement,tag1=value1,tag2=value2 field1=42i 1234567890")

        point.tags["tag1"].should eq("value1")
        point.tags["tag2"].should eq("value2")
      end
    end

    context "without timestamp" do
      it "parses name" do
        point = Point.parse("measurement field1=42i")

        point.name.should eq("measurement")
        point.time.should be_nil
      end
    end

    it "raises on invalid line protocol" do
      expect_raises(InvalidLineProtocolError) do
        Point.parse("invalid")
      end
    end
  end

  describe "#to_line_protocol" do
    it "generates correct line protocol with all components" do
      fields = {} of String => (Int64 | Float64 | String | Bool)
      fields["field1"] = 42_i64
      fields["field2"] = 3.14

      point = Point.new(
        name: "measurement",
        fields: fields,
        tags: {"tag1" => "value1"},
        time: 1234567890_i64
      )

      lp = point.to_line_protocol

      lp.should contain("measurement")
      lp.should contain("tag1=value1")
      lp.should contain("field1=42i")
      lp.should contain("field2=3.14")
      lp.should contain("1234567890")
    end

    it "generates correct line protocol without tags" do
      fields = {} of String => (Int64 | Float64 | String | Bool)
      fields["field1"] = 42_i64

      point = Point.new(
        name: "measurement",
        fields: fields,
        time: 1234567890_i64
      )

      lp = point.to_line_protocol

      lp.should eq("measurement field1=42i 1234567890")
    end

    it "generates correct line protocol without timestamp" do
      fields = {} of String => (Int64 | Float64 | String | Bool)
      fields["field1"] = 42_i64

      point = Point.new(
        name: "measurement",
        fields: fields
      )

      lp = point.to_line_protocol

      lp.should eq("measurement field1=42i")
    end
  end
end
