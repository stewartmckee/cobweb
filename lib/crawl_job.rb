class CrawlJob
  
  require "net/https"  
  require "uri"
  require "redis"
  require 'namespaced_redis'

  @queue = :cobweb_crawl_job

  def self.perform(content_request)
    
    # change all hash keys to symbols
    content_request = self.deep_symbolize_keys(content_request)
    
    content_request[:redis_options] = {} unless content_request.has_key? :redis_options
    @redis = NamespacedRedis.new(content_request[:redis_options], "cobweb-#{Cobweb.version}-#{content_request[:crawl_id]}")
    @stats = Stats.new(content_request)
    
    @debug = content_request[:debug]
    
    refresh_counters
    
    # check we haven't crawled this url before
    unless @redis.sismember "crawled", content_request[:url]
      @redis.srem "queued", content_request[:url]
      decrement_queue_counter
      @redis.sadd "crawled", content_request[:url]
      increment_crawl_counter
      
      # if there is no limit or we're still under it lets get the url
      if within_crawl_limits?(content_request[:crawl_limit])

        content = Cobweb.new(content_request).get(content_request[:url], content_request)
        
        ## update statistics
        @stats.update_statistics(content)
        
        # set the base url if this is the first page
        set_base_url @redis, content, content_request
        
        if within_queue_limits?(content_request[:crawl_limit])
          internal_links = all_links_from_content(content).map{|link| link.to_s}
        
          # reject the link if we've crawled it or queued it
          internal_links.reject!{|link| @redis.sismember("crawled", link)}
          internal_links.reject!{|link| @redis.sismember("queued", link)}
        
          # select the link if its internal
          internal_links.select!{|link| internal_link?(link)}

          internal_links.each do |link|
            enqueue_content(content_request, link) if within_queue_limits?(content_request[:crawl_limit])
          end
        end
        
        # enqueue to processing queue
        send_to_processing_queue(content, content_request)
        
        #if the enqueue counter has been requested update that
        if content_request.has_key? :enqueue_counter_key                                                                                  
          enqueue_redis = NamespacedRedis.new(content_request[:redis_options], content_request[:enqueue_counter_namespace].to_s)
          current_count = enqueue_redis.hget(content_request[:enqueue_counter_key], content_request[:enqueue_counter_field]).to_i
          enqueue_redis.hset(content_request[:enqueue_counter_key], content_request[:enqueue_counter_field], current_count+1)
        end

        # if there's nothing left queued or the crawled limit has been reached
        if content_request[:crawl_limit].nil? || content_request[:crawl_limit] == 0
          if @redis.scard("queued") == 0
            finished(content_request)
          end
        elsif @queue_counter == 0 || @crawl_counter >= content_request[:crawl_limit].to_i
          finished(content_request)
        end
      end
    else
      @redis.srem "queued", content_request[:url]
      decrement_queue_counter
      puts "Already crawled #{content_request[:url]}" if content_request[:debug]
    end

  end

  def self.finished(content_request)
    # finished
    @stats.end_crawl(content_request)
    Resque.enqueue(const_get(content_request[:crawl_finished_queue]), Stats.get_statistics.merge({:redis_options => content_request[:redis_options], :crawl_id => content_request[:crawl_id], :source_id => content_request[:source_id]}))                
  end

  def self.send_to_processing_queue(content, content_request)
    content_to_send = content.merge({:internal_urls => internal_patterns, :redis_options => content_request[:redis_options], :source_id => content_request[:source_id], :crawl_id => content_request[:crawl_id]})
    if content_request[:use_encoding_safe_process_job]
      content_to_send[:body] = Base64.encode64(content[:body])
      content_to_send[:processing_queue] = content_request[:processing_queue]
      Resque.enqueue(EncodingSafeProcessJob, content_to_send)
    else
      Resque.enqueue(const_get(content_request[:processing_queue]), content_to_send)
    end
    puts "#{content_request[:url]} has been sent for processing. use_encoding_safe_process_job: #{content_request[:use_encoding_safe_process_job]}" if content_request[:debug]
    puts "Crawled: #{@crawl_counter} Limit: #{content_request[:crawl_limit]} Queued: #{@queue_counter}" if content_request[:debug]
  end

  private
  
  def self.within_crawl_limits?(crawl_limit)
    crawl_limit.nil? or @crawl_counter < crawl_limit.to_i
  end
  
  def self.within_queue_limits?(crawl_limit)
    within_crawl_limits?(crawl_limit) and (crawl_limit.nil? or (@queue_counter + @crawl_counter) < crawl_limit.to_i)
  end
  
  def self.set_base_url(redis, content, content_request)
    if redis.get("base_url").nil?
      unless content[:redirect_through].nil? || content[:redirect_through].empty? || !content_request[:first_page_redirect_internal]
        uri = Addressable::URI.parse(content[:redirect_through].last)
        redis.sadd("internal_urls", [uri.scheme, "://", uri.host, "/*"].join)
      end
      redis.set("base_url", content[:url])
    end
  end
  
  def self.internal_link?(link)
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
  
  def self.internal_patterns
    @internal_patterns ||= @redis.smembers("internal_urls")
  end

  def self.all_links_from_content(content)
    links = content[:links].keys.map{|key| content[:links][key]}.flatten
    links.reject!{|link| link.starts_with?("javascript:")}
    links = links.map{|link| UriHelper.join_no_fragment(content[:url], link) }
    links.select!{|link| link.scheme == "http" || link.scheme == "https"}
    links.uniq
    links
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
  def self.deep_symbolize_keys(hash)
    hash.keys.each do |key|
      value = hash[key]
      hash.delete(key)
      hash[key.to_sym] = value
      if hash[key.to_sym].instance_of? Hash
        hash[key.to_sym] = self.deep_symbolize_keys(hash[key.to_sym])
      end
    end
    hash
  end
end
