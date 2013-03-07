require "nokogiri"

# ContentLinkParser extracts links from HTML content and assigns them to a hash based on the location the link was found.  The has contents can be configured in options, however, defaults to a pretty sensible default.
# Links can also be returned regardless of the location they were located and can be filtered by the scheme
class ContentLinkParser

  # Parses the content and absolutizes the urls based on url.  Options can be setup to determine the links that are extracted.
  def initialize(url, content, options = {})
    @options = {}.merge(options)
    @url = url
    @doc = Nokogiri::HTML(content)
    
    base_url = @url.to_s
    if @doc.at("base[href]")
      base_url = @doc.at("base[href]").attr("href").to_s
      @url = base_url if base_url
    end

    @options[:tags] = {}
    @options[:tags][:links] = [["a[href]", "href"], ["frame[src]", "src"], ["meta[@http-equiv=\"refresh\"]", "content"], ["link[href]:not([rel])", "href"], ["area[href]", "href"]]
    @options[:tags][:images] = [["img[src]", "src"]]
    @options[:tags][:related] = [["link[rel]", "href"]]
    @options[:tags][:scripts] = [["script[src]", "src"]]
    @options[:tags][:styles] = [["link[rel='stylesheet'][href]", "href"], ["style[@type^='text/css']", lambda{|array,tag|
      first_regex =/url\((['"]?)(.*?)\1\)/
      tag.content.scan(first_regex) {|match| array << Addressable::URI.parse(match[1]).to_s}
    }]]
    
    #clear the default tags if required
    @options[:tags] = {} if @options[:ignore_default_tags]
    @options[:tags].merge!(@options[:additional_tags]) unless @options[:additional_tags].nil?
    
  end
 
  # Returns a hash with arrays of links
  def link_data
    data = {}
    @options[:tags].keys.each do |key|
      data[key.to_sym] = self.instance_eval(key.to_s)
    end
    data
  end  
  
  # Returns an array of all absolutized links, specify :valid_schemes in options to limit to certain schemes.  Also filters repeating folders (ie if the crawler got in a link loop situation)
  def all_links(options = {})    
    options[:valid_schemes] = [:http, :https] unless options.has_key? :valid_schemes
    data = link_data
    links = data.keys.map{|key| data[key]}.flatten.uniq
    links = links.map{|link| UriHelper.join_no_fragment(@url, link).to_s }
    links = links.reject{|link| link =~ /\/([^\/]+?)\/\1\// }
    links = links.reject{|link| link =~ /([^\/]+?)\/([^\/]+?)\/.*?\1\/\2/ }    
    links = links.select{|link| options[:valid_schemes].include? link.split(':')[0].to_sym}
    links
  end
  
  # Returns the type of links as a method rather than using the hash e.g. 'content_link_parser.images'
  def method_missing(m)
    if @options[:tags].keys.include?(m)
      links = []
      @options[:tags][m].each do |selector, attribute|
        find_matches(links, selector, attribute)
      end
      links.uniq
    else
      super
    end
  end
  
  private
  # Processes the content to find links based on options[:tags]
  def find_matches(array, selector, attribute)
    if attribute.kind_of? String or attribute.kind_of? Symbol
      @doc.css(selector).each do |tag|
        begin
          array << Addressable::URI.parse(tag[attribute]).to_s
        rescue
        end
      end
    elsif attribute.instance_of? Regexp
      @doc.css(selector).each do |tag|
        begin
          tag.content.scan(attribute) {|match| array << Addressable::URI.parse(match[0]).to_s}
        rescue
        end
      end
    elsif attribute.instance_of? Proc
      @doc.css(selector).each do |tag|
        begin
          attribute.call(array, tag)
        rescue
        end
      end
    end
  end

end

