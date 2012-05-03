require 'rubygems'
require 'uri'
require 'resque'
require "addressable/uri"
require 'digest/sha1'
require 'base64'
require 'namespaced_redis'

Dir[File.dirname(__FILE__) + '/**/*.rb'].each do |file|
  require file
end

class Cobweb
  ## TASKS
  
  # redesign to have a resque stack and a single threaded stack
  # dry the code below, its got a lot of duplication
  # detect the end of the crawl (queued == 0 ?)
  # on end of crawl, return statistic hash (could call specified method ?) if single threaded or enqueue to a specified queue the stat hash
  # investigate using event machine for single threaded crawling
  
  def self.version
    CobwebVersion.version
  end
  
  def method_missing(method_sym, *arguments, &block)
    if method_sym.to_s =~ /^default_(.*)_to$/
      tag_name = method_sym.to_s.split("_")[1..-2].join("_").to_sym
      @options[tag_name] = arguments[0] unless @options.has_key?(tag_name)
    else
      super
    end
  end
  
  def initialize(options = {})
    @options = options
    default_use_encoding_safe_process_job_to  false
    default_follow_redirects_to               true
    default_redirect_limit_to                 10
    default_processing_queue_to               CobwebProcessJob
    default_crawl_finished_queue_to           CobwebFinishedJob
    default_quiet_to                          true
    default_debug_to                          false
    default_cache_to                          300
    default_timeout_to                        10
    default_redis_options_to                  Hash.new
    default_internal_urls_to                  []
    default_first_page_redirect_internal_to   true
    
  end
  
  def start(base_url)
    raise ":base_url is required" unless base_url
    request = {
      :crawl_id => Digest::SHA1.hexdigest("#{Time.now.to_i}.#{Time.now.usec}"),
      :url => base_url 
    }  
    
    if @options[:internal_urls].empty?
      uri = Addressable::URI.parse(base_url)
      @options[:internal_urls] << [uri.scheme, "://", uri.host, "/*"].join
    end
    
    request.merge!(@options)
    @redis = NamespacedRedis.new(request[:redis_options], "cobweb-#{Cobweb.version}-#{request[:crawl_id]}")
    @redis.hset "statistics", "queued_at", DateTime.now
    @redis.set("crawl-counter", 0)
    @redis.set("queue-counter", 1)
    
    @stats = Stats.new(request)
    @stats.start_crawl(request)
    
    # add internal_urls into redis
    @options[:internal_urls].map{|url| @redis.sadd("internal_urls", url)}
    
    Resque.enqueue(CrawlJob, request)
  end

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
      redis = NamespacedRedis.new(@options[:redis_options], "cobweb-#{Cobweb.version}-#{options[:crawl_id]}")
    else
      redis = NamespacedRedis.new(@options[:redis_options], "cobweb-#{Cobweb.version}")
    end
    
    content = {:base_url => url}
  
    # check if it has already been cached
    if redis.get(unique_id) and @options[:cache]
      puts "Cache hit for #{url}" unless @options[:quiet]
      content = deep_symbolize_keys(Marshal.load(redis.get(unique_id)))
    else
      # this url is valid for processing so lets get on with it
      #TODO the @http here is different from in head.  Should it be? - in head we are using a method-scoped variable.

      # retrieve data
      unless @http && @http.address == uri.host && @http.port == uri.inferred_port
        puts "Creating connection to #{uri.host}..." unless @options[:quiet]
        @http = Net::HTTP.new(uri.host, uri.inferred_port)
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
        request = Net::HTTP::Get.new uri.request_uri

        response = @http.request request
        
        if @options[:follow_redirects] and response.code.to_i >= 300 and response.code.to_i < 400
          puts "redirected... " unless @options[:quiet]
          
          # get location to redirect to
          url = UriHelper.join_no_fragment(uri, response['location'])
          
          # decrement redirect limit
          redirect_limit = redirect_limit - 1

          # raise exception if we're being redirected to somewhere we've been redirected to in this content request          
          #raise RedirectError("Loop detected in redirect for - #{url}") if content[:redirect_through].include? url
          
          # raise exception if redirect limit has reached 0
          raise RedirectError, "Redirect Limit reached" if redirect_limit == 0

          # get the content from redirect location
          content = get(url, options.merge(:redirect_limit => redirect_limit))
          content[:url] = uri.to_s
          content[:redirect_through] = [] if content[:redirect_through].nil?
          content[:redirect_through].insert(0, url)
        
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
          if content[:mime_type].include?("text/html") or content[:mime_type].include?("application/xhtml+xml")
            if response["Content-Encoding"]=="gzip"
              content[:body] = Zlib::GzipReader.new(StringIO.new(response.body)).read
            else
              content[:body] = response.body
            end
          else
            content[:body] = Base64.encode64(response.body)
          end
          content[:location] = response["location"]
          content[:headers] = deep_symbolize_keys(response.to_hash)
          # parse data for links
          link_parser = ContentLinkParser.new(content[:url], content[:body])
          content[:links] = link_parser.link_data
          
        end
        # add content to cache if required
        if @options[:cache]
          redis.set(unique_id, Marshal.dump(content))
          redis.expire unique_id, @options[:cache].to_i
        end
      rescue RedirectError => e
        puts "ERROR: #{e.message}"
        
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
        puts "ERROR: SocketError#{e.message}"
        
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
    end
    content  
  end
  
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
      redis = NamespacedRedis.new(@options[:redis_options], "cobweb-#{Cobweb.version}-#{options[:crawl_id]}")
    else
      redis = NamespacedRedis.new(@options[:redis_options], "cobweb-#{Cobweb.version}")
    end
    
    content = {}
    
    # check if it has already been cached
    if redis.get("head-#{unique_id}") and @options[:cache]
      puts "Cache hit for #{url}" unless @options[:quiet]
      content = deep_symbolize_keys(Marshal.load(redis.get("head-#{unique_id}")))
    else
      print "Retrieving #{url }... " unless @options[:quiet]

      # retrieve data
      http = Net::HTTP.new(uri.host, uri.inferred_port)
      if uri.scheme == "https"
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end 
      
      request_time = Time.now.to_f
      http.read_timeout = @options[:timeout].to_i
      http.open_timeout = @options[:timeout].to_i
      
      begin      
        request = Net::HTTP::Head.new uri.request_uri
        response = http.request request

        if @options[:follow_redirects] and response.code.to_i >= 300 and response.code.to_i < 400
          puts "redirected... " unless @options[:quiet]
          url = UriHelper.join_no_fragment(uri, response['location'])
          redirect_limit = redirect_limit - 1
          options = options.clone
          options[:redirect_limit]=redirect_limit
          content = head(url, options)
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
      rescue SocketError => e
        puts "ERROR: #{e.message}"
        
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
        puts "ERROR: #{e.message}"
        
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
  
  def deep_symbolize_keys(hash)
    hash.keys.each do |key|
      value = hash[key]
      hash.delete(key)
      hash[key.to_sym] = value
      if hash[key.to_sym].instance_of? Hash
        hash[key.to_sym] = deep_symbolize_keys(hash[key.to_sym])
      end
    end
    hash
  end
  
end
