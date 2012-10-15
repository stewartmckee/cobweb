require 'digest/md5'
require 'date'
require 'ap'
require 'redis-namespace'

# CobwebCrawler is a standalone crawler, it includes a built in statistics monitor using Sinatra.
class CobwebCrawler
  
  # See README for more information on options available
  def initialize(options={})
    @options = options
    
    @statistic = {}
    
    @options[:redis_options] = {:host => "127.0.0.1"} unless @options.has_key? :redis_options
    if @options.has_key? :crawl_id
      @crawl_id = @options[:crawl_id]
    else
      @crawl_id = Digest::MD5.hexdigest(DateTime.now.inspect.to_s)
      @options[:crawl_id] = @crawl_id
    end
    
    @redis = Redis::Namespace.new("cobweb-#{Cobweb.version}-#{@crawl_id}", :redis => Redis.new(@options[:redis_options]))
    @options[:internal_urls] = [] if @options[:internal_urls].nil?
    @options[:internal_urls].map{|url| @redis.sadd("internal_urls", url)}
    @debug = @options[:debug]
    
    @stats = Stats.new(@options.merge(:crawl_id => @crawl_id))
    if @options[:web_statistics]
      Server.start(@options)
    end
    
    @cobweb = Cobweb.new(@options)
  end
  
  # Initiates a crawl starting at the base_url and applying the options supplied. Can also take a block that is executed and passed content hash and statistic hash'
  def crawl(base_url, crawl_options = {}, &block)
    @options[:base_url] = base_url unless @options.has_key? :base_url
    
    @options[:internal_urls] << base_url if @options[:internal_urls].empty?
    @redis.sadd("internal_urls", base_url) if @options[:internal_urls].empty?
    
    @crawl_options = crawl_options
    
    @redis.sadd("queued", base_url) unless @redis.sismember("crawled", base_url) || @redis.sismember("queued", base_url)
    crawl_counter = @redis.scard("crawled").to_i
    queue_counter = @redis.scard("queued").to_i

    begin
      @stats.start_crawl(@options)
      while queue_counter>0 && (@options[:crawl_limit].to_i == 0 || @options[:crawl_limit].to_i > crawl_counter)      
        thread = Thread.new do
        
          url = @redis.spop "queued"
        
          @options[:url] = url
          unless @redis.sismember("crawled", url.to_s)
            begin
              @stats.update_status("Requesting #{url}...")
              content = @cobweb.get(url)
              @stats.update_status("Processing #{url}...")

              @redis.sadd "crawled", url.to_s
              @redis.incr "crawl-counter" 
              
              internal_links = ContentLinkParser.new(url, content[:body]).all_links(:valid_schemes => [:http, :https])

              # select the link if its internal (eliminate external before expensive lookups in queued and crawled)
              cobweb_links = CobwebLinks.new(@options)
              internal_links = internal_links.select{|link| cobweb_links.internal?(link)}
              
              # reject the link if we've crawled it or queued it
              internal_links.reject!{|link| @redis.sismember("crawled", link)}
              internal_links.reject!{|link| @redis.sismember("queued", link)}
              
              internal_links.each do |link|
                puts "Added #{link.to_s} to queue" if @debug
                @redis.sadd "queued", link
                queue_counter += 1
              end
              
              crawl_counter = crawl_counter + 1 #@redis.scard("crawled").to_i
              queue_counter = queue_counter - 1 #@redis.scard("queued").to_i
              
              @stats.update_statistics(content, crawl_counter, queue_counter)
              @stats.update_status("Completed #{url}.")
              yield content, @stats.get_statistics if block_given?

            rescue => e
              puts "!!!!!!!!!!!! ERROR !!!!!!!!!!!!!!!!"
              ap e
              ap e.backtrace
            end
          else
            puts "Already crawled #{@options[:url]}" if @debug
          end
        end
        thread.join
      end
    ensure
      @stats.end_crawl(@options)
    end
    @stats.get_statistics
  end
  
end

# Monkey patch into String a starts_with method
class String
  # Monkey patch into String a starts_with method
  def cobweb_starts_with?(val)
    if self.length >= val.length
      self[0..val.length-1] == val
    else
      false
    end
  end
end
