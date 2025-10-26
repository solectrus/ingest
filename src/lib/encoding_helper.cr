module EncodingHelper
  def self.clean_utf8(input : String) : String
    # Crystal strings are always valid UTF-8
    # This is a no-op in Crystal but kept for compatibility
    input
  end
end
