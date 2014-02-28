require 'rubygems'
require 'uri'
require 'resque'
require "addressable/uri"
require 'digest/sha1'
require 'base64'

Dir[File.dirname(__FILE__) + '/**/*.rb'].each do |file|
  require file
end

puts Gem::Specification.find_all_by_name("sidekiq", ">=3.0.0") 


# Cobweb class is used to perform get and head requests.  You can use this on its own if you wish without the crawler
class Cobweb
  
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
    default_user_agent_to                     "cobweb/#{Cobweb.version} (ruby/#{RUBY_VERSION} nokogiri/#{Nokogiri::VERSION})"
    default_valid_mime_types_to                ["*/*"]
    default_raise_exceptions_to               false
    default_store_inbound_links_to            false
    default_proxy_addr_to                     nil
    default_proxy_port_to                     nil

  end
  
  # This method starts the resque based crawl and enqueues the base_url
  def start(base_url)
    raise ":base_url is required" unless base_url
    request = {
      :crawl_id => Digest::SHA1.hexdigest("#{Time.now.to_i}.#{Time.now.usec}"),
      :url => base_url 
    }  
    
    if @options[:internal_urls].nil? || @options[:internal_urls].empty?
      uri = Addressable::URI.parse(base_url)
      @options[:internal_urls] = []
      @options[:internal_urls] << [uri.scheme, "://", uri.host, "/*"].join
      @options[:internal_urls] << [uri.scheme, "://", uri.host, ":", uri.inferred_port, "/*"].join
    end
    
    request.merge!(@options)
    @redis = Redis::Namespace.new("cobweb-#{Cobweb.version}-#{request[:crawl_id]}", :redis => RedisConnection.new(request[:redis_options]))
    @redis.set("original_base_url", base_url)
    @redis.hset "statistics", "queued_at", DateTime.now
    @redis.set("crawl-counter", 0)
    @redis.set("queue-counter", 1)

    @options[:seed_urls].map{|link| @redis.sadd "queued", link }
    
    @stats = Stats.new(request)
    @stats.start_crawl(request)
    
    # add internal_urls into redis
    @options[:internal_urls].map{|url| @redis.sadd("internal_urls", url)}
    if @options[:queue_system] == :resque
      Resque.enqueue(CrawlJob, request)
    elsif @options[:queue_system] == :sidekiq
      CrawlWorker.perform_async(request)
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
      redis = Redis::Namespace.new("cobweb-#{Cobweb.version}-#{options[:crawl_id]}", :redis => RedisConnection.new(@options[:redis_options]))
    else
      redis = Redis::Namespace.new("cobweb-#{Cobweb.version}", :redis => RedisConnection.new(@options[:redis_options]))
    end
    full_redis = Redis::Namespace.new("cobweb-#{Cobweb.version}", :redis => RedisConnection.new(@options[:redis_options]))

    content = {:base_url => url}

    # check if it has already been cached
    if ((@options[:cache_type] == :crawl_based && redis.get(unique_id)) || (@options[:cache_type] == :full && full_redis.get(unique_id))) && @options[:cache]
      if @options[:cache_type] == :crawl_based 
        puts "Cache hit in crawl for #{url}" unless @options[:quiet]
        content = HashUtil.deep_symbolize_keys(Marshal.load(redis.get(unique_id)))
      else
        puts "Cache hit for #{url}" unless @options[:quiet]
        content = HashUtil.deep_symbolize_keys(Marshal.load(full_redis.get(unique_id)))
      end
    else
      # retrieve data
      #unless @http && @http.address == uri.host && @http.port == uri.inferred_port
        puts "Creating connection to #{uri.host}..." if @options[:debug]
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
        puts "Retrieving #{uri}... " unless @options[:quiet]
        request_options={}
        request_options['Cookie']= options[:cookies] if options[:cookies]
        request_options['User-Agent']= options[:user_agent] if options.has_key?(:user_agent)

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

        if @options[:follow_redirects] and response.code.to_i >= 300 and response.code.to_i < 400

          # get location to redirect to
          uri = UriHelper.join_no_fragment(uri, response['location'])
          puts "Following Redirect to #{uri}... " unless @options[:quiet]

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
          
          puts "Retrieved." unless @options[:quiet]

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
            if response["Content-Encoding"]=="gzip"
              content[:body] = Zlib::GzipReader.new(StringIO.new(response.body)).read
            else
              content[:body] = response.body
            end
          else
            content[:body] = Base64.encode64(response.body)
          end
          content[:location] = response["location"]
          content[:headers] = HashUtil.deep_symbolize_keys(response.to_hash)
          # parse data for links
          link_parser = ContentLinkParser.new(content[:url], content[:body])
          content[:links] = link_parser.link_data
          
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
        puts "ERROR RedirectError: #{e.message}"
        
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
        puts "ERROR SocketError: #{e.message}"
        
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
        puts "ERROR Timeout::Error: #{e.message}"
        
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
      redis = Redis::Namespace.new("cobweb-#{Cobweb.version}-#{options[:crawl_id]}", :redis => RedisConnection.new(@options[:redis_options]))
    else
      redis = Redis::Namespace.new("cobweb-#{Cobweb.version}", :redis => RedisConnection.new(@options[:redis_options]))
    end
    
    content = {:base_url => url}
    
    # check if it has already been cached
    if redis.get("head-#{unique_id}") and @options[:cache]
      puts "Cache hit for #{url}" unless @options[:quiet]
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
        print "Retrieving #{url }... " unless @options[:quiet]
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
          puts "redirected... " unless @options[:quiet]

          uri = UriHelper.join_no_fragment(uri, response['location'])

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
            puts "Stored in cache [head-#{unique_id}]" if @options[:debug]
            redis.set("head-#{unique_id}", Marshal.dump(content))
            redis.expire "head-#{unique_id}", @options[:cache].to_i
          else
            puts "Not storing in cache as cache disabled" if @options[:debug]
          end
        end
      rescue RedirectError => e
        raise e if @options[:raise_exceptions]
        puts "ERROR RedirectError: #{e.message}"

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
        puts "ERROR SocketError: #{e.message}"
        
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
        puts "ERROR Timeout::Error: #{e.message}"
        
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

  def clear_cache
    
  end
  
  private
  # checks if the mime_type is textual
  def text_content?(content_type)
    @options[:text_mime_types].each do |mime_type|
      return true if content_type.match(Cobweb.escape_pattern_for_regex(mime_type))
    end
    false
  end
  
end
