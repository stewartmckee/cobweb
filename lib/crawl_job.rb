class CrawlJob
  
  require "net/https"  
  require "uri"
  require "redis"

  @queue = :cobweb_crawl_job

  def self.perform(content_request)
    
    # change all hash keys to symbols
    content_request = content_request.deep_symbolize_keys
    
    @redis = NamespacedRedis.new(Redis.new(content_request[:redis_options]), "cobweb-#{Cobweb.version}-#{content_request[:crawl_id]}")
    
    @absolutize = Absolutize.new(content_request[:url], :output_debug => false, :raise_exceptions => false, :force_escaping => false, :remove_anchors => true)
    @debug = content_request[:debug]
    
    refresh_counters
    
    # check we haven't crawled this url before
    unless @redis.sismember "crawled", content_request[:url]
      
      # if there is no limit or we're still under it lets get the url
      if content_request[:crawl_limit].nil? or @crawl_counter <= content_request[:crawl_limit].to_i
        content = Cobweb.new(content_request).get(content_request[:url], content_request)
        
        ## update statistics
        Stats.set_statistics_in_redis(@redis, content)
        
        # set the base url if this is the first page
        set_base_url @redis, content, content_request
        
        internal_links = all_links_from_content(content).map{|link| link.to_s}
        
        # reject the link if we've crawled it or queued it
        internal_links.reject!{|link| @redis.sismember("crawled", link)}
        internal_links.reject!{|link| @redis.sismember("queued", link)}
        
        # select the link if its internal
        internal_links.select!{|link| internal_link?(link)}

        internal_links.each do |link|
          enqueue_content(content_request, link)        
        end

        # now that we're done, lets update the queues
        @redis.srem "queued", content_request[:url]
        decrement_queue_counter
        @redis.sadd "crawled", content_request[:url]
        increment_crawl_counter

        # enqueue to processing queue
        Resque.enqueue(const_get(content_request[:processing_queue]), content.merge({:source_id => content_request[:source_id], :crawl_id => content_request[:crawl_id]}))
        puts "#{content_request[:url]} has been sent for processing." if content_request[:debug]
        puts "Crawled: #{@crawl_counter} Limit: #{content_request[:crawl_limit]} Queued: #{@queue_counter}" if content_request[:debug]
        
      else
        puts "Crawl Limit Exceeded by #{@crawl_counter - content_request[:crawl_limit].to_i} objects" if content_request[:debug]
      end
    else
      puts "Already crawled #{content_request[:url]}" if content_request[:debug]
    end

    # if the'res nothing left queued or the crawled limit has been reached
    if @queue_counter == 0 || @crawl_counter >= content_request[:crawl_limit].to_i
     
      puts "queue_counter: #{@queue_counter}"
      puts "crawl_counter: #{@crawl_counter}"
      puts "crawl_limit: #{content_request[:crawl_limit]}"

      # finished
      puts "FINISHED"
      stats = @redis.hgetall "statistics"
      stats[:total_pages] = @redis.get "total_pages"
      stats[:total_assets] = @redis.get "total_assets"
      stats[:crawl_counter] = @redis.get "crawl_counter"
      stats[:queue_counter] = @redis.get "queue_counter"
      stats[:crawled] = @redis.smembers "crawled"
      
      Resque.enqueue(const_get(content_request[:crawl_finished_queue]), stats.merge({:crawl_id => content_request[:crawl_id], :source_id => content_request[:source_id]}))            
      
    end
  end

  private
  def self.set_base_url(redis, content, content_request)
    if redis.get("base_url").nil?
      unless content[:redirect_through].empty? || !content_request[:first_page_redirect_internal]
        uri = Addressable::URI.parse(content[:redirect_through].last)
        redis.sadd("internal_urls", [uri.scheme, "://", uri.host, "/*"].join)
      end
      redis.set("base_url", content[:url])
    end
  end
  
  def self.internal_link?(link)
    puts "Checking for internal link for: #{link}" if @debug
    @internal_patterns ||= @redis.smembers("internal_urls").map{|pattern| Regexp.new("^#{pattern.gsub("*", ".*?")}")}
    valid_link = true
    @internal_patterns.each do |pattern|
      puts "Matching against #{pattern.source}" if @debug
      if link.match(pattern)
        puts "Matched as internal" if @debug
        return true
      end
    end
    puts "Didn't match any pattern so marked as not internal" if @debug
    false
  end

  def self.all_links_from_content(content)
    content[:links].keys.map{|key| content[:links][key]}.flatten
  end
  
  def self.enqueue_content(content_request, link)
    new_request = content_request.clone
    new_request[:url] = link
    new_request[:parent] = content_request[:url]
    Resque.enqueue(CrawlJob, new_request)
    @redis.sadd "queued", link
    increment_queue_counter
  end
  
  def self.increment_queue_counter
    @redis.incr "queue-counter"
    refresh_counters
  end
  def self.increment_crawl_counter
    @redis.incr "crawl-counter"
    refresh_counters
  end
  def self.decrement_queue_counter
    @redis.decr "queue-counter"
    refresh_counters
  end
  def self.refresh_counters
    @crawl_counter = @redis.get("crawl-counter").to_i
    @queue_counter = @redis.get("queue-counter").to_i
  end
  def self.reset_counters
    @redis.set("crawl-counter", @redis.smembers("crawled").count)
    @redis.set("queue-counter", @redis.smembers("queued").count)
    @crawl_counter = @redis.get("crawl-counter").to_i
    @queue_counter = @redis.get("queue-counter").to_i
  end
end
