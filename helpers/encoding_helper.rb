module EncodingHelper
  def self.clean_utf8(str)
    str = str.dup.force_encoding('UTF-8')
    str.valid_encoding? ? str : str.encode('UTF-8', invalid: :replace, undef: :replace, replace: '?')
  end
end
