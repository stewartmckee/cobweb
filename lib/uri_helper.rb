# Helper class to perform tasks on URI's
class UriHelper
  # Returns an Addressable::URI with the fragment section removed
  def self.join_no_fragment(content, link)
    begin
      new_link = Addressable::URI.join(content, link)
      new_link.fragment=nil
      return new_link
    rescue Addressable::URI::InvalidURIError
      return nil
    end
  end

  def self.parse(url)
    begin
      URI.parse(url)
    rescue URI::InvalidURIError
      begin
        URI.parse(URI.escape(url))
      rescue URI::InvalidURIError
        return nil # This seems to be a rotten link. Caller should check for nil
      end
    end
  end

end
