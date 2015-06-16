require "nokogiri"
require 'cobweb_links'

# ContentLinkParser extracts links from HTML content and assigns them to a hash based on the location the link was found.  The has contents can be configured in options, however, defaults to a pretty sensible default.
# Links can also be returned regardless of the location they were located and can be filtered by the scheme
class ContentLinkParser

  # Parses the content and absolutizes the urls based on url.  Options can be setup to determine the links that are extracted.
  def initialize(url, content, options = {})
    binding.pry
    @options = {}.merge(options)
    @url = url
    @doc = Nokogiri::HTML(content)

    if @doc.at("base[href]")
      base_url = @doc.at("base[href]").attr("href").to_s
      @url = base_url if base_url.present?
    end

    @options[:tags] = {}
    @options[:tags][:links] = [
      ["a[href]", "href"],
      ["frame[src]", "src"],
      ["link[href]:not([rel])", "href"],
      ["area[href]", "href"],
      ["meta[@http-equiv=\"refresh\"]", lambda{|array,tag|
        meta_link = parse_meta_refresh_content_link(tag["content"])
        array << meta_link unless meta_link.nil?
        array
      }],
      ["meta[@http-equiv=\"REFRESH\"]", lambda{|array,tag|
        meta_link = parse_meta_refresh_content_link(tag["content"])
        array << meta_link unless meta_link.nil?
        array
      }],
    ]
    @options[:tags][:images] = [["img[src]", "src"]]
    @options[:tags][:related] = [["link[rel]", "href"]]
    @options[:tags][:scripts] = [["script[src]", "src"]]
    @options[:tags][:styles] = [
      ["link[rel='stylesheet'][href]", "href"],
      ["link[rel='STYLESHEET'][href]", "href"],
      ["style[@type^='text/css']", lambda{|array,tag|
        first_regex =/url\((['"]?)(.*?)\1\)/
        tag.content.scan(first_regex) {|match| array << Addressable::URI.parse(match[1]).to_s}
      }],
      ["style[@type^='TEXT/CSS']", lambda{|array,tag|
        first_regex =/url\((['"]?)(.*?)\1\)/
        tag.content.scan(first_regex) {|match| array << Addressable::URI.parse(match[1]).to_s}
      }],
    ]

    #clear the default tags if required
    @options[:tags] = {} if @options[:ignore_default_tags]
    @options[:tags].merge!(@options[:additional_tags]) unless @options[:additional_tags].nil?

  end

  def parse_meta_refresh_content_link meta_content
    meta_link = meta_content.gsub(" ", "").scan(/url=(\S+)/iu)
    if meta_link.is_a?(Array)
      meta_link = meta_link.flatten[0].to_s.gsub(/["']/, '')
      meta_link = nil if meta_link == ''
    end
    meta_link = meta_content.gsub(" ", "") if meta_link.nil?
    meta_link = meta_link.to_s.gsub(/["']/, '') unless meta_link.nil?
    if meta_link.nil?
      log_error "CantParseMetaRefreshLink #{meta_content}"
    end
    meta_link
  end

  # extracts link data from nokogiri with attributes on each link (rel, follow, anchor text, title, alt)
  def full_link_data
    full_link_data = []
    options_to_check = @options[:tags][:links] + @options[:tags][:images]
    Array(options_to_check).each do |selector, attribute|
      @doc.css(selector).each do |node|
        if attribute == "href"
          full_link_data << {"text" => node.text.to_s, "rel" => node["rel"], "link" => UriHelper.join_no_fragment(@url, node["href"].to_s).to_s , "alt" => node["alt"].to_s, "title" => node["title"].to_s, "type" => "link" }
        elsif attribute == "src" && selector == "img[src]"
          full_link_data << {"rel" => node["rel"], "link" => UriHelper.join_no_fragment(@url, node["src"].to_s).to_s, "alt" => node["alt"].to_s, "rel" => node["rel"].to_s, "title" => node["title"].to_s, "type" => "image"}
        end
      end
    end
    full_link_data
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
    # TODO parameter sorting to get them where they don't have dupes if the
    # parameters are in different order in different places
    options[:valid_schemes] = [:http, :https] unless options.has_key? :valid_schemes
    data = link_data

    links = data.keys.map{|key| data[key]}.flatten.uniq
    links = links.map{|link| UriHelper.join_no_fragment(@url, link).to_s }
    links = links.reject{|link| link =~ /\/([^\/]+?)\/\1\// }
    links = links.reject{|link| link =~ /([^\/]+?)\/([^\/]+?)\/.*?\1\/\2/ }
    links = links.reject{|link| link =~ /\/([^\/]+\.js)/ } if @options[:exclude_js]
    links = links.reject{|link| link =~ /\/([^\/]+\.css)/ } if @options[:exclude_css]
    links = links.select{|link| options[:valid_schemes].include? link.split(':')[0].to_sym}

    # removes parameters from links if they are provided by the options
    # array
    Array(@options[:remove_parameters]).each do |param|
      links = links.map{|prelink| remove_parameter(prelink, param) }
    end if Array(@options[:remove_parameters]).length > 0
    links
  end

  # helper with internal/external link checks
  def cobweb_links_helper
    @cobweb_links_helper ||= CobwebLinks.new(@options)
  end

  # returns the list of external links
  def external_links
    external_links = []
    all_links.each do |link|
      external_links << link if cobweb_links_helper.external?(link)
    end
    external_links
  end

  # returns the list of internal links
  def internal_links
    internal_links = []
    all_links.each do |link|
      internal_links << link if cobweb_links_helper.internal?(link)
    end
    internal_links
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

  #remove a tracking parameter or other item from a URL
  # extracted from Oma::Url
  def remove_parameter(url, parameter)
    uri = Addressable::URI.parse(url)
    params = uri.query_values
    unless params.blank?
      params.delete(parameter)
    end
    uri.query_values = params
    url = uri.to_s.gsub(/\?$/, "")
    url
  end

  # extract a parameter value from a URL
  # copied in for convenience for now, I'm sure there's a use
  # for this (removal of GA parameters, etc.)
  def get_parameter(url, parameter)
    uri = Addressable::URI.parse(url)
    params = uri.query_values
    params[parameter]
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

