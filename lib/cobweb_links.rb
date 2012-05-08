class CobwebLinks
  
  # processes links supplied to it
  def initialize(options={})
    @options = options
    
    raise InternalUrlsMissingError, ":internal_urls is required" unless @options.has_key? :internal_urls
    raise InvalidUrlsError, ":internal_urls must be an array" unless @options[:internal_urls].kind_of? Array
    raise InvalidUrlsError, ":external_urls must be an array" unless !@options.has_key?(:external_urls) || @options[:external_urls].kind_of?(Array)
    @options[:external_urls] = [] unless @options.has_key? :external_urls
    @options[:debug] = false unless @options.has_key? :debug
    
    @internal_patterns = @options[:internal_urls].map{|pattern| Regexp.new("^#{pattern.gsub(".", "\\.").gsub("?", "\\?").gsub("*", ".*?")}")}
    @external_patterns = @options[:external_urls].map{|pattern| Regexp.new("^#{pattern.gsub(".", "\\.").gsub("?", "\\?").gsub("*", ".*?")}")}
    
  end
  
  def internal?(link)
    if @options[:debug]
      puts "--------------------------------"
      puts "Link: #{link}"
      puts "Internal matches"
      ap @internal_patterns.select{|pattern| link.match(pattern)}
      puts "External matches"
      ap @external_patterns.select{|pattern| link.match(pattern)}
    end
    !@internal_patterns.select{|pattern| link.match(pattern)}.empty? && @external_patterns.select{|pattern| link.match(pattern)}.empty?
  end
  
  def external?(link)
    if @options[:debug]
      puts "--------------------------------"
      puts "Link: #{link}"
      puts "Internal matches"
      ap @internal_patterns.select{|pattern| link.match(pattern)}
      puts "External matches"
      ap @external_patterns.select{|pattern| link.match(pattern)}
    end
    @internal_patterns.select{|pattern| link.match(pattern)}.empty? || !@external_patterns.select{|pattern| link.match(pattern)}.empty?
  end
  
end

class InternalUrlsMissingError < Exception
end  
class InvalidUrlsError < Exception
end

