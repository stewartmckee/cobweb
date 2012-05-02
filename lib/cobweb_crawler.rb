require 'digest/md5'
require 'date'
require 'ap'
#require 'namespaced_redis'

class CobwebCrawler
  
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
    
    @redis = NamespacedRedis.new(@options[:redis_options], "cobweb-#{@crawl_id}")
    @options[:internal_urls] = [] if @options[:internal_urls].nil?
    @options[:internal_urls].map{|url| @redis.sadd("internal_urls", url)}
    @debug = @options[:debug]
    
    @stats = Stats.new(@options.merge(:crawl_id => @crawl_id))
    if @options[:web_statistics]
      Server.start
    end
    
    @cobweb = Cobweb.new(@options)
  end
  
  def crawl(base_url, crawl_options = {}, &block)
    @options[:base_url] = base_url unless @options.has_key? :base_url
    
    @options[:internal_urls] << base_url if @options[:internal_urls].empty?
    @redis.sadd("internal_urls", base_url) if @options[:internal_urls].empty?
    
    @crawl_options = crawl_options
    
    puts "http://localhost:4567/statistics/#{@crawl_id}"
    puts ""
    
    @redis.sadd "queued", base_url
    crawl_counter = @redis.scard("crawled").to_i
    queue_counter = @redis.scard("queued").to_i

    begin
      @stats.start_crawl(@options)
      while queue_counter>0 && (@options[:crawl_limit].to_i == 0 || @options[:crawl_limit].to_i > crawl_counter)      
        thread = Thread.new do
        
          url = @redis.spop "queued"
          crawl_counter = @redis.scard("crawled").to_i
          queue_counter = @redis.scard("queued").to_i
        
          @options[:url] = url
          unless @redis.sismember("crawled", url.to_s)
            begin
              @stats.update_status("Requesting #{url}...")
              content = @cobweb.get(url)
              @stats.update_status("Processing #{url}...")

              @redis.sadd "crawled", url.to_s
              @redis.incr "crawl-counter" 
            
              internal_links = all_links_from_content(content).map{|link| link.to_s}

              # reject the link if we've crawled it or queued it
              internal_links.reject!{|link| @redis.sismember("crawled", link)}
              internal_links.reject!{|link| @redis.sismember("queued", link)}
            

              # select the link if its internal
              internal_links.select!{|link| internal_link?(link)}

              internal_links.each do |link|
                puts "Added #{link.to_s} to queue" if @debug
                @redis.sadd "queued", link
              end
            
              crawl_counter = @redis.scard("crawled").to_i
              queue_counter = @redis.scard("queued").to_i

              @stats.update_statistics(content)
              @stats.update_status("Completed #{url}.")
              puts "Crawled: #{crawl_counter.to_i} Limit: #{@options[:crawl_limit].to_i} Queued: #{queue_counter.to_i}" if @debug 
       
              yield content, @statistic if block_given?

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
  
  
  def internal_link?(link)
    puts "Checking internal link for: #{link}" if @debug
    valid_link = true
    internal_patterns.map{|pattern| Regexp.new("^#{pattern.gsub("*", ".*?")}")}.each do |pattern|
      puts "Matching against #{pattern.source}" if @debug
      if link.match(pattern)
        puts "Matched as internal" if @debug
        return true
      end
    end
    puts "Didn't match any pattern so marked as not internal" if @debug
    false
  end
  
  def internal_patterns
    @internal_patterns ||= @redis.smembers("internal_urls")
  end

  def all_links_from_content(content)
    links = content[:links].keys.map{|key| content[:links][key]}.flatten
    links.reject!{|link| link.starts_with?("javascript:")}
    links = links.map{|link| UriHelper.join_no_fragment(content[:url], link) }
    links.select!{|link| link.scheme == "http" || link.scheme == "https"}
    links.uniq
    links
  end
end

class String
  def starts_with?(val)
    if self.length >= val.length
      self[0..val.length-1] == val
    else
      false
    end
  end
end
