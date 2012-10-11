module Cobweb
  class CrawlObject
    
    def initialize(content_hash)
      @content = HashUtil.deep_symbolize_keys(content_hash)
      @options = @content
    end
    
    
    # Helper method to determine if this content is to be processed or not
    def permitted_type?
      @options[:valid_mime_types].each do |mime_type|
        return true if mime_type.match(Cobweb.escape_pattern_for_regex(mime_type))
      end
      false
    end
    
    def mime_type
      @content[:mime_type]
    end
    
    def body
      @content[:body]
    end
    
  end
end