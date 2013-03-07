
# CobwebLinks processes links to determine whether they are internal or external links
class CobwebLinks
  
  # Initalise's internal and external patterns and sets up regular expressions
  def initialize(options={})
    @options = options
    
    raise InternalUrlsMissingError, ":internal_urls is required" unless @options.has_key? :internal_urls
    raise InvalidUrlsError, ":internal_urls must be an array" unless @options[:internal_urls].kind_of? Array
    raise InvalidUrlsError, ":external_urls must be an array" unless !@options.has_key?(:external_urls) || @options[:external_urls].kind_of?(Array)
    @options[:external_urls] = [] unless @options.has_key? :external_urls
    @options[:debug] = false unless @options.has_key? :debug
    
    @internal_patterns = @options[:internal_urls].map{|pattern| Regexp.new("^#{Cobweb.escape_pattern_for_regex(pattern)}")}
    @external_patterns = @options[:external_urls].map{|pattern| Regexp.new("^#{Cobweb.escape_pattern_for_regex(pattern)}")}
    
  end
  
  def allowed?(link)
    if @options[:obey_robots]
      robot = Robots.new(:url => link, :user_agent => @options[:user_agent])
      return robot.allowed?(link)
    else
      return true
    end
  end
  
  # Returns true if the link is matched to an internal_url and not matched to an external_url
  def internal?(link)
    !@internal_patterns.select{|pattern| link.match(pattern)}.empty? && @external_patterns.select{|pattern| link.match(pattern)}.empty?
  end
  
  # Returns true if the link is matched to an external_url or not matched to an internal_url
  def external?(link)
    @internal_patterns.select{|pattern| link.match(pattern)}.empty? || !@external_patterns.select{|pattern| link.match(pattern)}.empty?
  end

  def matches_external?(link)
    !@external_patterns.select{|pattern| link.match(pattern)}.empty?
  end
  
end

# Exception raised for :internal_urls missing from CobwebLinks
class InternalUrlsMissingError < Exception
end  
# Exception raised for :internal_urls being invalid from CobwebLinks
class InvalidUrlsError < Exception
end

