require "../spec_helper"

describe EnvLoader do
  describe ".load" do
    it "loads environment variables from file" do
      # Create a temporary .env file
      file_path = "/tmp/test_env_#{Time.utc.to_unix_ms}.env"

      File.write(file_path, <<-ENV)
      TEST_VAR1=value1
      TEST_VAR2=value2
      ENV

      begin
        EnvLoader.load(file_path)

        ENV["TEST_VAR1"].should eq("value1")
        ENV["TEST_VAR2"].should eq("value2")
      ensure
        File.delete(file_path)
        ENV.delete("TEST_VAR1")
        ENV.delete("TEST_VAR2")
      end
    end

    it "supports empty values" do
      file_path = "/tmp/test_env_#{Time.utc.to_unix_ms}.env"

      File.write(file_path, "TEST_EMPTY=\n")

      begin
        EnvLoader.load(file_path)

        ENV["TEST_EMPTY"].should eq("")
      ensure
        File.delete(file_path)
        ENV.delete("TEST_EMPTY")
      end
    end

    it "supports quoted values" do
      file_path = "/tmp/test_env_#{Time.utc.to_unix_ms}.env"

      File.write(file_path, <<-ENV)
      TEST_DOUBLE_QUOTED="double quoted"
      TEST_SINGLE_QUOTED='single quoted'
      ENV

      begin
        EnvLoader.load(file_path)

        ENV["TEST_DOUBLE_QUOTED"].should eq("double quoted")
        ENV["TEST_SINGLE_QUOTED"].should eq("single quoted")
      ensure
        File.delete(file_path)
        ENV.delete("TEST_DOUBLE_QUOTED")
        ENV.delete("TEST_SINGLE_QUOTED")
      end
    end

    it "skips comments and empty lines" do
      file_path = "/tmp/test_env_#{Time.utc.to_unix_ms}.env"

      File.write(file_path, <<-ENV)
      # This is a comment
      TEST_VAR=value

      # Another comment
      ENV

      begin
        EnvLoader.load(file_path)

        ENV["TEST_VAR"].should eq("value")
      ensure
        File.delete(file_path)
        ENV.delete("TEST_VAR")
      end
    end

    it "does not override existing environment variables" do
      ENV["TEST_EXISTING"] = "original"

      file_path = "/tmp/test_env_#{Time.utc.to_unix_ms}.env"
      File.write(file_path, "TEST_EXISTING=from_file\n")

      begin
        EnvLoader.load(file_path)

        ENV["TEST_EXISTING"].should eq("original")
      ensure
        File.delete(file_path)
        ENV.delete("TEST_EXISTING")
      end
    end

    it "does nothing if file does not exist" do
      EnvLoader.load("/tmp/nonexistent_#{Time.utc.to_unix_ms}.env")
      # Should not raise error
    end
  end
end
