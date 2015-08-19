module CobwebModule
  class CrawlObject

    def initialize(content_hash, options={})
      @content = HashUtil.deep_symbolize_keys(content_hash)
      @options = options
    end


    # Helper method to determine if this content is to be processed or not
    # only does a mime check if the page has content. Otherwise, it's assumed
    # as true
    def permitted_type?
      if @content[:status_code] && @content[:status_code] == 200
        @options[:valid_mime_types].each do |valid_mime_type|
          return true if @content[:mime_type].match(Cobweb.escape_pattern_for_regex(valid_mime_type))
        end
        false
      else
        true
      end
    end

    def method_missing(m)
      if @content.keys.include? m.to_sym
        @content[m.to_sym]
      else
        super
      end
    end

    def to_hash
      @content
    end
  end
end
