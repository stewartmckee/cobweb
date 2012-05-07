
class ContentLinkParser

  require "nokogiri"

  def initialize(url, content, options = {})
    @options = options
    @url = url
    @doc = Nokogiri::HTML(content)
    
    base_url = @url.to_s
    if @doc.at("base[href]")
      base_url = @doc.at("base[href]").attr("href").to_s
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
 
  def link_data
    data = {}
    @options[:tags].keys.each do |key|
      data[key.to_sym] = self.instance_eval(key.to_s)
    end
    data
  end  
  
  def all_links(options = {})    
    options[:valid_schemes] = [:http, :https] unless options.has_key? :valid_schemes
    data = link_data
    links = data.keys.map{|key| data[key]}.flatten.uniq
    links = links.map{|link| UriHelper.join_no_fragment(@url, link).to_s }
    links = links.select{|link| options[:valid_schemes].include? link.split(':')[0].to_sym}
    links
  end
  
  def method_missing(m)
    if @options[:tags].keys.include?(m)
      links = []
      @options[:tags][m].each do |selector, attribute|
        find_matches(links, selector, attribute)
      end
      links.uniq
    else
      puts "Warning: There was no configuration on how to find #{m} links"
      []
    end
  end
  
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

