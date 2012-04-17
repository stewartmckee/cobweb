class UriHelper
  def self.join_no_fragment(content, link)
    new_link = Addressable::URI.join(content, link)
    new_link.fragment=nil
    new_link
  end

end