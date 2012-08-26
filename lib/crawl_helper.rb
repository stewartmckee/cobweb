class CrawlHelper

  require "net/https"  
  require "uri"
  require "redis"
  require 'namespaced_redis'
  
  def self.crawl_page(content_request)
    # change all hash keys to symbols
    content_request = HashUtil.deep_symbolize_keys(content_request)
    @content_request = content_request
    
    content_request[:redis_options] = {} unless content_request.has_key? :redis_options
    content_request[:crawl_limit_by_page] = false unless content_request.has_key? :crawl_limit_by_page
    content_request[:valid_mime_types] = ["*/*"] unless content_request.has_key? :valid_mime_types
    content_request[:queue_system] = content_request[:queue_system].to_sym
    
    @redis = NamespacedRedis.new(content_request[:redis_options], "cobweb-#{Cobweb.version}-#{content_request[:crawl_id]}")
    @stats = Stats.new(content_request)
    
    @debug = content_request[:debug]
    
    decrement_queue_counter
    
    # check we haven't crawled this url before
    unless @redis.sismember "crawled", content_request[:url]
      # if there is no limit or we're still under it lets get the url
      if within_crawl_limits?(content_request[:crawl_limit])
        content = Cobweb.new(content_request).get(content_request[:url], content_request)
        if content_request[:url] == @redis.get("original_base_url")
           @redis.set("crawled_base_url", content[:base_url])
        end
        if is_permitted_type(content)
          begin
            # move the url from the queued list to the crawled list - for both the original url, and the content url (to handle redirects)
            @redis.srem "queued", content_request[:url]
            @redis.sadd "crawled", content_request[:url]
            @redis.srem "queued", content[:url]
            @redis.sadd "crawled", content[:url]
            # increment the counter if we are not limiting by page only || we are limiting count by page and it is a page
            if content_request[:crawl_limit_by_page]
              if content[:mime_type].match("text/html")
                increment_crawl_started_counter
              end
            else
              increment_crawl_started_counter
            end

            ## update statistics
            @stats.update_status("Crawling #{content_request[:url]}...")
            @stats.update_statistics(content)

            # set the base url if this is the first page
            set_base_url @redis, content, content_request

            @cobweb_links = CobwebLinks.new(content_request)
            if within_queue_limits?(content_request[:crawl_limit])
              internal_links = ContentLinkParser.new(content_request[:url], content[:body], content_request).all_links(:valid_schemes => [:http, :https])

              # select the link if its internal
              internal_links.select! { |link| @cobweb_links.internal?(link) }

              # reject the link if we've crawled it or queued it
              internal_links.reject! { |link| @redis.sismember("crawled", link) }
              internal_links.reject! { |link| @redis.sismember("queued", link) }

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

          ensure
            #update the queued and crawled lists if we are within the crawl limits.

            # update the queue and crawl counts -- doing this very late in the piece so that the following transaction all occurs at once.
            # really we should do this with a lock https://github.com/PatrickTulskie/redis-lock
            if content_request[:crawl_limit_by_page]
              if content[:mime_type].match("text/html")
                increment_crawl_counter
              end
            else
              increment_crawl_counter
            end
            puts "Crawled: #{@crawl_counter} Limit: #{content_request[:crawl_limit]} Queued: #{@queue_counter} In Progress: #{@crawl_started_counter-@crawl_counter}" if @debug
          end
        else
          puts "ignoring #{content_request[:url]} as mime_type is #{content[:mime_type]}" if content_request[:debug]
        end
      else
        puts "ignoring #{content_request[:url]} as outside of crawl limits." if content_request[:debug]
      end
      
    else
      @redis.srem "queued", content_request[:url]
      puts "Already crawled #{content_request[:url]}" if content_request[:debug]
    end
    
    # if there's nothing left queued or the crawled limit has been reached
    refresh_counters
    if content_request[:crawl_limit].nil? || content_request[:crawl_limit] == 0
      if @queue_counter+@crawl_started_counter-@crawl_counter == 0
        finished(content_request)
      end
    elsif (@queue_counter +@crawl_started_counter-@crawl_counter)== 0 || @crawl_counter >= content_request[:crawl_limit].to_i
      finished(content_request)
    end
    
  end

  # Sets the crawl status to 'Crawl Finished' and enqueues the crawl finished job
  def self.finished(content_request)
    # finished
    if @redis.hget("statistics", "current_status")!= "Crawl Finished"
      ap "CRAWL FINISHED  #{content_request[:url]}, #{counters}, #{@redis.get("original_base_url")}, #{@redis.get("crawled_base_url")}" if content_request[:debug]
      @stats.end_crawl(content_request)
      
      additional_stats = {:crawl_id => content_request[:crawl_id], :crawled_base_url => @redis.get("crawled_base_url")}
      additional_stats[:redis_options] = content_request[:redis_options] unless content_request[:redis_options] == {}
      additional_stats[:source_id] = content_request[:source_id] unless content_request[:source_id].nil?
      
      if content_request[:queue_system] == :resque
        Resque.enqueue(const_get(content_request[:crawl_finished_queue]), @stats.get_statistics.merge(additional_stats))
      elsif content_request[:queue_system] == :sidekiq
        puts "Queueing Finished on Sidekiq"
        const_get(content_request[:crawl_finished_queue]).perform_async(@stats.get_statistics.merge(additional_stats))
      else
        raise "Unknown queue system: #{content_request[:queue_system]}"
      end
    else
      # nothing to report here, we're skipping the remaining urls as we're outside of the crawl limit
    end
  end
  
  # Enqueues the content to the processing queue setup in options
  def self.send_to_processing_queue(content, content_request)
    content_to_send = content.merge({:internal_urls => content_request[:internal_urls], :redis_options => content_request[:redis_options], :source_id => content_request[:source_id], :crawl_id => content_request[:crawl_id]})
    if content_request[:direct_call_process_job]
      clazz = const_get(content_request[:processing_queue])
      clazz.perform(content_to_send)
    elsif content_request[:use_encoding_safe_process_job]
      content_to_send[:body] = Base64.encode64(content[:body])
      content_to_send[:processing_queue] = content_request[:processing_queue]
      Resque.enqueue(EncodingSafeProcessJob, content_to_send)
    else
      if content_request[:queue_system] == :resque
        Resque.enqueue(const_get(content_request[:processing_queue]), content_to_send)
      elsif content_request[:queue_system] == :sidekiq
        puts "Queueing on Sidekiq"
        const_get(content_request[:processing_queue]).perform_async(content_to_send)
      else
        raise "Unknown queue system: #{content_request[:queue_system]}"
      end
    end
    puts "#{content_request[:url]} has been sent for processing. use_encoding_safe_process_job: #{content_request[:use_encoding_safe_process_job]}" if content_request[:debug]
  end

  private
  
  # Helper method to determine if this content is to be processed or not
  def self.is_permitted_type(content)
    @content_request[:valid_mime_types].each do |mime_type|
      return true if content[:mime_type].match(Cobweb.escape_pattern_for_regex(mime_type))
    end
    false
  end
  
  # Returns true if the crawl count is within limits
  def self.within_crawl_limits?(crawl_limit)
    refresh_counters
    crawl_limit.nil? or @crawl_started_counter < crawl_limit.to_i
  end
  
  # Returns true if the queue count is calculated to be still within limits when complete
  def self.within_queue_limits?(crawl_limit)
    refresh_counters
    (@content_request[:crawl_limit_by_page]&& (crawl_limit.nil? or @crawl_counter < crawl_limit.to_i)) || within_crawl_limits?(crawl_limit) && (crawl_limit.nil? || (@queue_counter + @crawl_counter) < crawl_limit.to_i)
  end
  
  # Sets the base url in redis.  If the first page is a redirect, it sets the base_url to the destination
  def self.set_base_url(redis, content, content_request)
    if redis.get("base_url").nil?
      unless content[:redirect_through].nil? || content[:redirect_through].empty? || !content_request[:first_page_redirect_internal]
        uri = Addressable::URI.parse(content[:redirect_through].last)
        redis.sadd("internal_urls", [uri.scheme, "://", uri.host, "/*"].join)
      end
      redis.set("base_url", content[:url])
    end
  end
  
  # Enqueues content to the crawl_job queue
  def self.enqueue_content(content_request, link)
    new_request = content_request.clone
    new_request[:url] = link
    new_request[:parent] = content_request[:url]
    if content_request[:queue_system] == :resque
      Resque.enqueue(CrawlJob, new_request)
    elsif content_request[:queue_system] == :sidekiq
      puts "Queueing content on Sidekiq"
      CrawlWorker.perform_async(new_request)
    else
      raise "Unknown queue system: #{content_request[:queue_system]}"
    end
    @redis.sadd "queued", link
    increment_queue_counter
  end
  
  # Increments the queue counter and refreshes crawl counters
  def self.increment_queue_counter
    @redis.incr "queue-counter"
    refresh_counters
  end
  # Increments the crawl counter and refreshes crawl counters
  def self.increment_crawl_counter
    @redis.incr "crawl-counter"
    refresh_counters
  end
  def self.increment_crawl_started_counter
    @redis.incr "crawl-started-counter"
    refresh_counters
  end
  # Decrements the queue counter and refreshes crawl counters
  def self.decrement_queue_counter
    @redis.decr "queue-counter"
    refresh_counters
  end
  # Refreshes the crawl counters
  def self.refresh_counters
    @crawl_counter = @redis.get("crawl-counter").to_i
    @crawl_started_counter = @redis.get("crawl-started-counter").to_i
    @queue_counter = @redis.get("queue-counter").to_i
  end
  
  def self.print_counters
    puts counters
  end

  def self.counters
    "@crawl_counter: #{@crawl_counter} @crawl_started_counter: #{@crawl_started_counter} @queue_counter: #{@queue_counter}"
  end
end