module Cobweb
  class Crawl
    
    def initialize(options={})
      @options = HashUtil.deep_symbolize_keys(options)
      
      setup_defaults
      @redis = NamespacedRedis.new(@options[:redis_options], "cobweb-#{Cobweb.version}-#{@options[:crawl_id]}")
      @stats = Stats.new(@options)
      @debug = content_request[:debug]
      
    end
    
    # Returns true if the url requested is already in the crawled queue
    def already_crawled?
       @redis.sismember "crawled", @options[:url]
    end
    
    # Returns true if the crawl count is within limits
    def within_crawl_limits?
      @options[:crawl_limit].nil? or crawl_counter < @options[:crawl_limit].to_i
    end

    # Returns true if the queue count is calculated to be still within limits when complete
    def within_queue_limits?
      (@options[:crawl_limit_by_page]&& (@options[:crawl_limit].nil? or crawl_counter < @options[:crawl_limit].to_i)) || within_crawl_limits? && (@options[:crawl_limit].nil? || (queue_counter + crawl_counter) < @options[:crawl_limit].to_i)
    end
    
    def retrieve
      if within_crawl_limit?
        @stats.update_status("Retrieving #{content_request[:url]}...")
        @content = Cobweb.new(@options).get(@options[:url], @options)
        if @options[:url] == @redis.get("original_base_url")
           @redis.set("crawled_base_url", @content[:base_url])
        end
      
        ## update statistics
        @stats.update_statistics(@content)
        true
      else
        false
      end
    end
    
    def process_links &block
      
      # set the base url if this is the first page
      set_base_url @redis, content, @options
      
      @cobweb_links = CobwebLinks.new(@options)
      if within_queue_limits?
        internal_links = ContentLinkParser.new(@options[:url], content.body, @options).all_links(:valid_schemes => [:http, :https])
        #get rid of duplicate links in the same page.
        internal_links.uniq!
        # select the link if its internal
        internal_links.select! { |link| @cobweb_links.internal?(link) }

        # reject the link if we've crawled it or queued it
        internal_links.reject! { |link| @redis.sismember("crawled", link) }
        internal_links.reject! { |link| @redis.sismember("queued", link) }

        internal_links.each do |link|
          if within_queue_limits?
            if @crawl_helper.status != CobwebCrawlHelper::CANCELLED
              yield link if block_given
              unless link.nil?
                @redis.sadd "queued", link
                increment_queue_counter
              end
            else
              puts "Cannot enqueue new content as crawl has been cancelled." if content_request[:debug]
            end
          end
        end
      end
    end
    
    def content
      unless defined? @content || !@content.nil?
        retrieve
      end
      @content
    end
    
    def update_queues
      @redis.incr "inprogress"
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
    end
    
    def finished?
      # if there's nothing left queued or the crawled limit has been reached
      if @options[:crawl_limit].nil? || @options[:crawl_limit] == 0
        if queue_counter + crawl_started_counter - crawl_counter == 0
          return true
        end
      elsif (queue_counter+crawl_started_counter-crawl_counter)== 0 || crawl_counter >= @options[:crawl_limit].to_i
        return true
      end
      false
    end
    
    private
    def setup_defaults
      @options[:redis_options] = {} unless @options.has_key? :redis_options
      @options[:crawl_limit_by_page] = false unless @options.has_key? :crawl_limit_by_page
      @options[:valid_mime_types] = ["*/*"] unless @options.has_key? :valid_mime_types
    end

    # Increments the queue counter and refreshes crawl counters
    def self.increment_queue_counter
      @redis.incr "queue-counter"
    end
    # Increments the crawl counter and refreshes crawl counters
    def self.increment_crawl_counter
      @redis.incr "crawl-counter"
    end
    def self.increment_crawl_started_counter
      @redis.incr "crawl-started-counter"
    end
    # Decrements the queue counter and refreshes crawl counters
    def self.decrement_queue_counter
      @redis.decr "queue-counter"
    end

    def self.crawl_counter
      @redis.get("crawl-counter").to_i
    end
    def self.queue_counter
      @redis.get("queue-counter").to_i
    end

    def self.print_counters
      puts counters
    end

    def self.counters
      "crawl_counter: #{crawl_counter} crawl_started_counter: #{crawl_started_counter} queue_counter: #{queue_counter}"
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


    
  end
end