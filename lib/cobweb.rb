require 'rubygems'
require 'uri'
require "addressable/uri"
require 'digest/sha1'
require 'base64'

# local files
require 'content_link_parser'
require 'document'
require 'crawl_job'
require 'cobweb_process_job'
require 'redis_connection'
require 'crawl_process_worker'
require 'cobweb_crawl_helper'
require 'cobweb_stats'
require 'cobweb'
require 'robots'
require 'encoding_safe_process_job'
require 'cobweb_finished_job'
require 'report_command'
require 'crawl'
require 'crawl_object'
require 'hash_util'
require 'redirect_error'
require 'cobweb_dsl'
require 'uri_helper'

if Gem::Specification.find_all_by_name("resque", ">=1.0.0").count >= 1
  RESQUE_INSTALLED = true
  require 'resque'
else
  RESQUE_INSTALLED = false
  puts "resque gem not installed, skipping crawl_job specs"
end

# Cobweb class is used to perform get and head requests.  You can use this on its own if you wish without the crawler
class Cobweb

  attr_reader :options

  # retrieves current version
  def self.version
    CobwebVersion.version
  end

  # used for setting default options
  def method_missing(method_sym, *arguments, &block)
    if method_sym.to_s =~ /^default_(.*)_to$/
      tag_name = method_sym.to_s.split("_")[1..-2].join("_").to_sym
      @options[tag_name] = arguments[0] unless @options.has_key?(tag_name)
    else
      super
    end
  end

  # See readme for more information on options available
  def initialize(options = {})
    @options = options
    @options[:data] = {} if @options[:data].nil?
    default_use_encoding_safe_process_job_to  false
    default_follow_redirects_to               true
    default_redirect_limit_to                 10
    default_queue_system_to                   :resque
    if @options[:queue_system] == :resque
      default_processing_queue_to               "CobwebProcessJob"
      default_crawl_finished_queue_to           "CobwebFinishedJob"
    else
      default_processing_queue_to               "CrawlProcessWorker"
      default_crawl_finished_queue_to           "CrawlFinishedWorker"
    end
    default_quiet_to                          true
    default_debug_to                          false
    default_cache_to                          300
    default_cache_type_to                     :crawl_based # other option is :full
    default_timeout_to                        10
    default_redis_options_to                  Hash.new
    default_internal_urls_to                  []
    default_external_urls_to                  []
    default_seed_urls_to                  []
    default_first_page_redirect_internal_to   true
    default_text_mime_types_to                ["text/*", "application/xhtml+xml"]
    default_obey_robots_to                    false
    default_user_agent_to                     "BoBoBot 1.0 (ruby/#{RUBY_VERSION} nokogiri/#{Nokogiri::VERSION})"
    default_valid_mime_types_to                ["*/*"]
    default_raise_exceptions_to               false
    default_store_inbound_links_to            false
    default_proxy_addr_to                     nil
    default_proxy_port_to                     nil

  end

  def logger
    @logger ||= Logger.new(STDOUT)
  end

  def crawl_id
    @crawl_id ||= begin
      if @options[:crawl_id]
        @options[:crawl_id]
      else
        Digest::SHA1.hexdigest("#{Time.now.to_i}.#{Time.now.usec}")
      end
    end
  end

  # This method starts the resque based crawl and enqueues the base_url
  def start(base_url,start_urls=[])
    raise ":base_url is required" unless base_url
    request = {
      :crawl_id => crawl_id,
      :url => base_url
    }

    if @options[:internal_urls].nil? || @options[:internal_urls].empty?
      uri = Addressable::URI.parse(base_url)
      @options[:internal_urls] = []
      @options[:internal_urls] << [uri.scheme, "://", uri.host, "/*"].join
      @options[:internal_urls] << [uri.scheme, "://", uri.host, ":", uri.inferred_port, "/*"].join
    end

    request.merge!(@options)

    # set initial depth
    request[:depth] = 1
    @redis = Redis::Namespace.new("cobweb:#{request[:crawl_id]}", :redis => RedisConnection.new(request[:redis_options]))
    @redis.set("original_base_url", base_url)
    @redis.hset "statistics", "queued_at", DateTime.now
    @redis.set("crawl-counter", 0)
    @redis.set("queue-counter", 1)

    # adds the @options["data"] to the global space so it can be retrieved with a simple redis query
    if @options[:data]
      @options[:data].keys.each do |key|
        @redis.hset "data", key.to_s, @options[:data][key]
      end
    end

    # setup robots delay
    #if @options[:respect_robots_delay]
    #  @robots = robots_constructor(base_url, @options)
    #  delay_set = @robots.delay || 0.5 # should be setup as an options with a default value
    #  @redis.set("robots:per_page_delay", delay_set)
    #  @redis.set("robots:next_retrieval", Time.now)
    #end

    @options[:seed_urls].map{|link| @redis.sadd "queued", link }

    @stats = CobwebStats.new(request)
    @stats.start_crawl(request)

    # add internal_urls into redis
    @options[:internal_urls].map{|url| @redis.sadd("internal_urls", url)}
    if @options[:queue_system] == :resque
      # multiple start urls
      start_urls.each do |start_url|
        request[:url] = start_url
        Resque.enqueue(CrawlJob, request)
      end


      # single base_url
      request[:url] = base_url
      if start_urls.empty?
        Resque.enqueue(CrawlJob, request)
      end
    else
      raise "Unknown queue system: #{content_request[:queue_system]}"
    end

    request
  end

  # Returns array of cookies from content
  def get_cookies(response)
    all_cookies = response.get_fields('set-cookie')
    unless all_cookies.nil?
      cookies_array = Array.new
      all_cookies.each { |cookie|
        cookies_array.push(cookie.split('; ')[0])
      }
      cookies = cookies_array.join('; ')
    end
  end

  # Performs a HTTP GET request to the specified url applying the options supplied
  def get(url, options = @options)
    raise "url cannot be nil" if url.nil?
    uri = Addressable::URI.parse(url)
    uri.normalize!
    uri.fragment=nil
    url = uri.to_s

    # get the unique id for this request
    unique_id = Digest::SHA1.hexdigest(url.to_s)
    if options.has_key?(:redirect_limit) and !options[:redirect_limit].nil?
      redirect_limit = options[:redirect_limit].to_i
    else
      redirect_limit = 10
    end

    # connect to redis
    if options.has_key? :crawl_id
      redis = Redis::Namespace.new("cobweb:#{options[:crawl_id]}", :redis => RedisConnection.new(@options[:redis_options]))
    else
      redis = Redis::Namespace.new("cobweb", :redis => RedisConnection.new(@options[:redis_options]))
    end
    full_redis = Redis::Namespace.new("cobweb", :redis => RedisConnection.new(@options[:redis_options]))

    content = {:base_url => url}

    # check if it has already been cached
    if ((@options[:cache_type] == :crawl_based && redis.get(unique_id)) || (@options[:cache_type] == :full && full_redis.get(unique_id))) && @options[:cache]
      if @options[:cache_type] == :crawl_based
        logger.info "Cache hit in crawl for #{url}" unless @options[:quiet]
        content = HashUtil.deep_symbolize_keys(Marshal.load(redis.get(unique_id)))
      else
        logger.info "Cache hit for #{url}" unless @options[:quiet]
        content = HashUtil.deep_symbolize_keys(Marshal.load(full_redis.get(unique_id)))
      end
    else
      # retrieve data
      #unless @http && @http.address == uri.host && @http.port == uri.inferred_port
        logger.debug "Creating connection to #{uri.host}..." if @options[:debug]
        @http = Net::HTTP.new(uri.host, uri.inferred_port, @options[:proxy_addr], @options[:proxy_port])
      #end
      if uri.scheme == "https"
        @http.use_ssl = true
        @http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end

      request_time = Time.now.to_f
      @http.read_timeout = @options[:timeout].to_i
      @http.open_timeout = @options[:timeout].to_i
      begin
        logger.info "Retrieving #{uri}... " unless @options[:quiet]
        request_options={}
        request_options['Cookie']= options[:cookies] if options[:cookies]
        request_options['User-Agent']= options[:user_agent] if options.has_key?(:user_agent)
        request_options['Accept-Encoding'] = 'identity' # This is used to accept

        request = Net::HTTP::Get.new uri.request_uri, request_options
        # authentication
        if @options[:authentication] == "basic"
          raise ":username and :password are required if using basic authentication" unless @options[:username] && @options[:password]
          request.basic_auth @options[:username], @options[:password]
        end
        if @options[:range]
          request.set_range(@options[:range])
        end

        response = @http.request request
        content[:response_charset] = response_charset response

        if @options[:follow_redirects] and response.code.to_i >= 300 and response.code.to_i < 400

          # get location to redirect to
          uri = UriHelper.join_no_fragment(uri, response['location'])
          raise RedirectError, "Invalid redirect uri #{response['location']}" unless uri.present?

          logger.info "Following Redirect to #{uri}... " unless @options[:quiet]

          # decrement redirect limit
          redirect_limit = redirect_limit - 1

          raise RedirectError, "Redirect Limit reached" if redirect_limit == 0
          cookies = get_cookies(response)

          # get the content from redirect location
          content = get(uri, options.merge(:redirect_limit => redirect_limit, :cookies => cookies))

          content[:redirect_through] = [uri.to_s] if content[:redirect_through].nil?
          content[:redirect_through].insert(0, url)
          content[:url] = content[:redirect_through].last

          content[:response_time] = Time.now.to_f - request_time
        else
          content[:response_time] = Time.now.to_f - request_time

          logger.info "Retrieved." unless @options[:quiet]

          # create the content container
          content[:url] = uri.to_s
          content[:status_code] = response.code.to_i
          content[:mime_type] = ""
          content[:mime_type] = response.content_type.split(";")[0].strip unless response.content_type.nil?

          if !response["Content-Type"].nil? && response["Content-Type"].include?(";")
            charset = response["Content-Type"][response["Content-Type"].index(";")+2..-1] if !response["Content-Type"].nil? and response["Content-Type"].include?(";")
            charset = charset[charset.index("=")+1..-1] if charset and charset.include?("=")
            content[:character_set] = charset
          end

          content[:length] = response.content_length
          content[:text_content] = text_content?(content[:mime_type])

          if text_content?(content[:mime_type])
            content[:body] = response.body
            if response["Content-Encoding"]=="gzip"
              content[:body] = Zlib::GzipReader.new(StringIO.new(content[:body])).read
            end
            if charset = guessed_charset(response) # favours response
              content[:body_charset] = body_charset response.body
              content[:body].force_encoding(charset).encode('utf-8')
            end
          else
            content[:body] = Base64.encode64(response.body) unless response.body.nil?
          end

          content[:location] = response["location"]
          content[:headers] = HashUtil.deep_symbolize_keys(response.to_hash)

          # parse data for links
          link_parser = ContentLinkParser.new(content[:url], content[:body], @options)

          content[:links] = link_parser.link_data
          content[:links][:external] = link_parser.external_links
          content[:links][:internal] = link_parser.internal_links

          # add an array of images with their attributes for image processing
          content[:images] = []
          if @options[:store_image_attributes]
            Array(link_parser.full_link_data.select {|link| link["type"] == "image"}).each do |inbound_link|
              inbound_link["link"] = UriHelper.parse(inbound_link["link"])
              content[:images] << inbound_link if inbound_link["link"].present?
            end
          end

        end
        # add content to cache if required
        if @options[:cache]
          if @options[:cache_type] == :crawl_based
            redis.set(unique_id, Marshal.dump(content))
            redis.expire unique_id, @options[:cache].to_i
          else
            full_redis.set(unique_id, Marshal.dump(content))
            full_redis.expire unique_id, @options[:cache].to_i
          end
        end
      rescue RedirectError => e
        raise e if @options[:raise_exceptions]
        logger.error "ERROR RedirectError: #{e.message}"

        ## generate a blank content
        content = {}
        content[:url] = uri.to_s
        content[:response_time] = Time.now.to_f - request_time
        content[:status_code] = 0
        content[:length] = 0
        content[:body] = ""
        content[:error] = e.message
        content[:images] = []
        content[:mime_type] = "error/dnslookup"
        content[:headers] = {}
        content[:links] = {}

      rescue SocketError => e
        raise e if @options[:raise_exceptions]
        logger.error "ERROR SocketError: #{e.message}"

        ## generate a blank content
        content = {}
        content[:url] = uri.to_s
        content[:response_time] = Time.now.to_f - request_time
        content[:status_code] = 0
        content[:length] = 0
        content[:body] = ""
        content[:images] = []
        content[:error] = e.message
        content[:mime_type] = "error/dnslookup"
        content[:headers] = {}
        content[:links] = {}

      rescue Timeout::Error => e
        raise e if @options[:raise_exceptions]
        logger.error "ERROR Timeout::Error: #{e.message}"

        ## generate a blank content
        content = {}
        content[:url] = uri.to_s
        content[:response_time] = Time.now.to_f - request_time
        content[:status_code] = 0
        content[:length] = 0
        content[:images] = []
        content[:body] = ""
        content[:error] = e.message
        content[:mime_type] = "error/serverdown"
        content[:headers] = {}
        content[:links] = {}
      end
      content
    end
  end

  # Performs a HTTP HEAD request to the specified url applying the options supplied
  def head(url, options = @options)
    raise "url cannot be nil" if url.nil?
    uri = Addressable::URI.parse(url)
    uri.normalize!
    uri.fragment=nil
    url = uri.to_s

    # get the unique id for this request
    unique_id = Digest::SHA1.hexdigest(url)
    if options.has_key?(:redirect_limit) and !options[:redirect_limit].nil?
      redirect_limit = options[:redirect_limit].to_i
    else
      redirect_limit = 10
    end

    # connect to redis
    if options.has_key? :crawl_id
      redis = Redis::Namespace.new("cobweb:#{options[:crawl_id]}:", :redis => RedisConnection.new(@options[:redis_options]))
    else
      redis = Redis::Namespace.new("cobweb", :redis => RedisConnection.new(@options[:redis_options]))
    end

    content = {:base_url => url}

    # check if it has already been cached
    if redis.get("head-#{unique_id}") and @options[:cache]
      logger.info "Cache hit for #{url}" unless @options[:quiet]
      content = HashUtil.deep_symbolize_keys(Marshal.load(redis.get("head-#{unique_id}")))
    else
      # retrieve data
      unless @http && @http.address == uri.host && @http.port == uri.inferred_port
        puts "Creating connection to #{uri.host}..." unless @options[:quiet]
        @http = Net::HTTP.new(uri.host, uri.inferred_port, @options[:proxy_addr], @options[:proxy_port])
      end
      if uri.scheme == "https"
        @http.use_ssl = true
        @http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end

      request_time = Time.now.to_f
      @http.read_timeout = @options[:timeout].to_i
      @http.open_timeout = @options[:timeout].to_i
      begin
        logger.info "Retrieving #{url }... " unless @options[:quiet]
        request_options={}
        if options[:cookies]
          request_options[ 'Cookie']= options[:cookies]
        end
        request = Net::HTTP::Head.new uri.request_uri, request_options
        # authentication
        if @options[:authentication] == "basic"
          raise ":username and :password are required if using basic authentication" unless @options[:username] && @options[:password]
          request.basic_auth @options[:username], @options[:password]
        end

        response = @http.request request

        if @options[:follow_redirects] and response.code.to_i >= 300 and response.code.to_i < 400
          logger.info "redirected... " unless @options[:quiet]

          uri = UriHelper.join_no_fragment(uri, response['location'])
          raise RedirectError, "Invalid redirect uri #{response['location']}" unless uri.present?

          redirect_limit = redirect_limit - 1

          raise RedirectError, "Redirect Limit reached" if redirect_limit == 0
          cookies = get_cookies(response)

          content = head(uri, options.merge(:redirect_limit => redirect_limit, :cookies => cookies))
          content[:url] = uri.to_s
          content[:redirect_through] = [] if content[:redirect_through].nil?
          content[:redirect_through].insert(0, url)
        else
          content[:url] = uri.to_s
          content[:status_code] = response.code.to_i
          unless response.content_type.nil?
            content[:mime_type] = response.content_type.split(";")[0].strip
            if response["Content-Type"].include? ";"
              charset = response["Content-Type"][response["Content-Type"].index(";")+2..-1] if !response["Content-Type"].nil? and response["Content-Type"].include?(";")
              charset = charset[charset.index("=")+1..-1] if charset and charset.include?("=")
              content[:character_set] = charset
            end
          end

          # add content to cache if required
          if @options[:cache]
            logger.info "Stored in cache [head-#{unique_id}]" if @options[:debug]
            redis.set("head-#{unique_id}", Marshal.dump(content))
            redis.expire "head-#{unique_id}", @options[:cache].to_i
          else
            puts "Not storing in cache as cache disabled" if @options[:debug]
          end
        end
      rescue RedirectError => e
        raise e if @options[:raise_exceptions]
        logger.error "ERROR RedirectError: #{e.message}"

        ## generate a blank content
        content = {}
        content[:url] = uri.to_s
        content[:response_time] = Time.now.to_f - request_time
        content[:status_code] = 0
        content[:length] = 0
        content[:body] = ""
        content[:error] = e.message
        content[:mime_type] = "error/dnslookup"
        content[:headers] = {}
        content[:links] = {}

      rescue SocketError => e
        raise e if @options[:raise_exceptions]
        logger.error "ERROR SocketError: #{e.message}"

        ## generate a blank content
        content = {}
        content[:url] = uri.to_s
        content[:response_time] = Time.now.to_f - request_time
        content[:status_code] = 0
        content[:length] = 0
        content[:body] = ""
        content[:error] = e.message
        content[:mime_type] = "error/dnslookup"
        content[:headers] = {}
        content[:links] = {}

      rescue Timeout::Error => e
        raise e if @options[:raise_exceptions]
        logger.error "ERROR Timeout::Error: #{e.message}"

        ## generate a blank content
        content = {}
        content[:url] = uri.to_s
        content[:response_time] = Time.now.to_f - request_time
        content[:status_code] = 0
        content[:length] = 0
        content[:body] = ""
        content[:error] = e.message
        content[:mime_type] = "error/serverdown"
        content[:headers] = {}
        content[:links] = {}
      end

      content
    end

  end

  # escapes characters with meaning in regular expressions and adds wildcard expression
  def self.escape_pattern_for_regex(pattern)
    pattern = pattern.gsub(".", "\\.")
    pattern = pattern.gsub("?", "\\?")
    pattern = pattern.gsub("+", "\\+")
    pattern = pattern.gsub("*", ".*?")
    pattern
  end

  def clear_cache;end

  def robots_constructor(base_url, options)
    Robots.new(:url => base_url, :user_agent => options[:user_agent])
  end

  private
  # checks if the mime_type is textual
  def text_content?(content_type)
    @options[:text_mime_types].each do |mime_type|
      return true if content_type.match(Cobweb.escape_pattern_for_regex(mime_type))
    end
    false
  end


  def guessed_charset response
    response_charset(response) || body_charset(response.body)
  end

  def response_charset response
    charset = nil
    response.type_params.each_pair do |k,v|
      charset = v.upcase if k =~ /charset/i
    end
    charset
  end

  def body_charset body
    return nil if body.nil?
    body_charset = nil
    unless body_charset # HTML 5
      body_charset = body =~ /<meta[^>]*charset=["'](.*?)["']/i && $1.upcase
    end
    unless body_charset # HTML 5
      body_charset = body =~ /<meta[^>]*?charset=([^"']+)/i && $1
    end
    body_charset
  end

end
