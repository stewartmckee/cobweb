module CobwebModule
  class Crawl
    attr_accessor :redis

    def initialize(options={})
      @options = HashUtil.deep_symbolize_keys(options)

      setup_defaults

      @redis = Redis::Namespace.new("cobweb:#{@options[:crawl_id]}", :redis => RedisConnection.new(@options[:redis_options]))
      @stats = CobwebStats.new(@options)
      @debug = @options[:debug]
      @first_to_finish = false

    end

    def logger
      @logger ||= Logger.new(STDOUT)
    end

    # Returns true if the url requested is already in the crawled queue
    def already_crawled?(link=@options[:url])
      @redis.sismember "crawled", link
    end

    def already_queued?(link)
      @redis.sismember "queued", link
    end

    def already_running?(link)
      @redis.sismember "currently_running", link
    end

    def already_handled?(link)
      already_crawled?(link) || already_queued?(link) || already_running?(link)
    end

    # Returns true if the crawl count is within limits
    def within_crawl_limits?
      @options[:crawl_limit].nil? || crawl_counter < @options[:crawl_limit].to_i
    end

    # Returns true if the processed count is within limits
    def within_process_limits?
      @options[:crawl_limit].nil? || process_counter < @options[:crawl_limit].to_i
    end

    # Returns true if the queue count is calculated to be still within limits when complete
    def within_queue_limits?

      # if we are limiting by page we can't limit the queue size as we don't know the mime type until retrieved
      if @options[:crawl_limit_by_page]
        return true

        # if a crawl limit is set, limit queue size to crawled + queue
      elsif @options[:crawl_limit].to_i > 0
        (queue_counter + crawl_counter) < @options[:crawl_limit].to_i

        # no crawl limit set so always within queue limit
      else
        true
      end
    end

    def retrieve

      unless already_running? @options[:url]
        unless already_crawled? @options[:url]
          update_queues
          if within_crawl_limits?
            @redis.sadd("currently_running", @options[:url])
            @stats.update_status("Retrieving #{@options[:url]}...")
            @content = Cobweb.new(@options).get(@options[:url], @options)
            update_counters

            if @options[:url] == @redis.get("original_base_url")
              @redis.set("crawled_base_url", @content[:base_url])
            end

            if content.permitted_type?

              @stats.update_statistics(@content)
              logger.info "CRAWLED #{@options[:url]}"
              return true
            else
              logger.info "NOT PERMITTED #{@options[:url]}"
            end
          else
            logger.info "OUTWITH CRAWL LIMITS #{@options[:url]}"
            decrement_queue_counter
          end
        else
          logger.info "ALREADY CRAWLED #{@options[:url]}"
          decrement_queue_counter
        end
      else
        debug_puts "\n\nDETECTED DUPLICATE JOB for #{@options[:url]}\n"
        debug_ap @redis.smembers("currently_running")
        decrement_queue_counter
      end
      false
    end

    # extract it out so it can be used in multiple methods
    def content_link_parser
      @content_link_parser ||= ContentLinkParser.new(@options[:url], content.body, @options)
    end

    def store_graph_data
      begin
        # store the links from this page linking TO other pages for
        # retrieval and processing of the inbound link processing in finishing stages
        if @options[:store_inbound_links] && Array(content_link_parser.internal_links).length > 0
          source_url_hexdigest = Digest::MD5.hexdigest(content.url.to_s)
          Array(content_link_parser.internal_links).each do |link|
            begin
              uri = URI.parse(link)
            rescue URI::InvalidURIError
              uri = URI.parse(URI.encode(link))
            end
            destination_url_hexdigest = Digest::MD5.hexdigest(uri.to_s)
            unless source_url_hexdigest == destination_url_hexdigest
              @redis.sadd("inbound_links:#{destination_url_hexdigest}",
                         source_url_hexdigest) if ["http", "https"].include?(uri.scheme)
            end
          end
        end


        if @options[:store_inbound_anchor_text]
          Array(content_link_parser.full_link_data.select {|link| link["type"] == "link"}).each do |inbound_link|
            target_uri = UriHelper.parse(inbound_link["link"])
            unless content.url.to_s == target_uri.to_s
              @redis.sadd("inbound_anchors:#{Digest::MD5.hexdigest(target_uri.to_s)}", inbound_link["text"].downcase )
            end
          end
        end

      rescue => e
        # binding.pry
        logger.warn "#{e.inspect} #{e.backtrace}"
      end

    end

    def redirect_links
      # handle redirect cases by adding location to the queue
      rfq = []
      if [302,301].include?(content.status_code)
        link = content.headers[:location].first.to_s rescue nil
        if link && @cobweb_links.internal?(link)
          rfq = link
        end
      end
      rfq
    end

    def process_links &block

      # set the base url if this is the first page
      set_base_url @redis

      @cobweb_links = CobwebLinks.new(@options)
      if within_queue_limits?

        # reparse the link content
        content_link_parser = ContentLinkParser.new(@options[:url], content.body, @options)
        document_links = content_link_parser.all_links(:valid_schemes => [:http, :https])

        #get rid of duplicate links in the same page.
        document_links.uniq!

        # select the link if its internal
        internal_links = document_links.select{ |link| @cobweb_links.internal?(link) }
        external_links = document_links.select{ |link| !@cobweb_links.internal?(link) }

        # reject the link if we've crawled it or queued it

        internal_links.reject! { |link| already_handled?(link)}

        lock("internal-links") do
          internal_links.each do |link|
            if within_queue_limits? && !already_handled?(link)
              if status != CobwebCrawlHelper::CANCELLED
                yield link if block_given?
                unless link.nil?
                  @redis.sadd "queued", link
                  increment_queue_counter
                end
              else
                debug_puts "Cannot enqueue new content as crawl has been cancelled."
              end
            end
          end
        end
      end
    end

    def content
      raise "Content is not available" if @content.nil?
      CobwebModule::CrawlObject.new(@content, @options)
    end

    def update_queues
      lock("update_queues") do
        #@redis.incr "inprogress"
        # move the url from the queued list to the crawled list - for both the original url, and the content url (to handle redirects)
        @redis.srem "queued", @options[:url]
        @redis.sadd "crawled", @options[:url]

        # increment the counter if we are not limiting by page only || we are limiting count by page and it is a page
      end
    end

    def update_counters
      if @options[:crawl_limit_by_page]
        if content.mime_type.match("text/html")
          increment_crawl_counter
        end
      else
        increment_crawl_counter
      end
      decrement_queue_counter
    end

    def to_be_processed?
      !finished? && within_process_limits? && !already_queued?(@options[:url])
    end

    def process(&block)
      lock("process-count") do
        if @options[:crawl_limit_by_page]
          if content.mime_type.match("text/html")
            increment_process_counter
          end
        else
          increment_process_counter
        end
        #@redis.sadd "queued", @options[:url]
      end

      yield if block_given?
      @redis.incr("crawl_job_enqueued_count")
    end

    def finished_processing
      @redis.srem "currently_running", @options[:url]
    end

    def finished?
      # print_counters
      # debug_puts @stats.get_status
      if @stats.get_status == CobwebCrawlHelper::FINISHED
        debug_puts "Already Finished!"
      end
      # if there's nothing left queued or the crawled limit has been reached and we're not still processing something
      if @options[:crawl_limit].nil? || @options[:crawl_limit] == 0
        if queue_counter == 0 && @redis.smembers("currently_running").empty?
          debug_puts "queue_counter is 0 and currently_running is empty so we're done"
          #finished
          return true
        end
      elsif (queue_counter == 0 || process_counter >= @options[:crawl_limit].to_i) && @redis.smembers("currently_running").empty?
        #finished
        debug_puts "queue_counter: #{queue_counter}, @redis.smembers(\"currently_running\").empty?: #{@redis.smembers("currently_running").empty?}, process_counter: #{process_counter}, @options[:crawl_limit].to_i: #{@options[:crawl_limit].to_i}"
        return true
      end
      false
    end

    def finish
      debug_puts ""
      debug_puts "========================================================================"
      debug_puts "finished crawl on #{@options[:url]}"
      print_counters
      debug_puts "========================================================================"
      debug_puts ""

      set_first_to_finish
      @stats.end_crawl(@options)
    end

    def set_first_to_finish
      @redis.watch("first_to_finish") do
        if !@redis.exists("first_to_finish")
          @redis.multi do
            debug_puts "set first to finish"
            @first_to_finish = true
            @redis.set("first_to_finish", 1)
          end
        else
          @redis.unwatch
        end
      end
    end


    def first_to_finish?
      @first_to_finish
    end

    def crawled_base_url
      @redis.get("crawled_base_url")
    end

    def statistics
      @stats.get_statistics
    end

    def redis
      @redis
    end

    def lock(key, &block)
      debug_puts "REQUESTING LOCK [#{key}]"
      set_nx = @redis.setnx("#{key}_lock", "locked")
      debug_puts "LOCK:#{key}:#{set_nx}"
      while !set_nx
        debug_puts "===== WAITING FOR LOCK [#{key}] ====="
        sleep 0.01
        set_nx = @redis.setnx("#{key}_lock", "locked")
      end

      debug_puts "RECEIVED LOCK [#{key}]"
      @redis.expire("#{key}_lock", 30)
      begin
        result = yield
      ensure
        @redis.del("#{key}_lock")
        #debug_puts "LOCK RELEASED [#{key}]"
      end
      result
    end

    def debug_ap(value)
      ap(value) if @options[:debug]
    end

    def debug_puts(value)
      logger.info value if @options[:debug]
    end

    def setup_defaults
      @options[:redis_options] = {} unless @options.has_key? :redis_options
      @options[:crawl_limit_by_page] = false unless @options.has_key? :crawl_limit_by_page
      @options[:valid_mime_types] = ["*/*"] unless @options.has_key? :valid_mime_types
    end

    # Increments the queue counter and refreshes crawl counters
    def increment_queue_counter
      @redis.incr "queue-counter"
    end
    # Increments the crawl counter and refreshes crawl counters
    def increment_crawl_counter
      @redis.incr "crawl-counter"
    end
    # Increments the process counter
    def increment_process_counter
      @redis.incr "process-counter"
    end
    # Decrements the queue counter and refreshes crawl counters
    def decrement_queue_counter
      @redis.decr "queue-counter"
    end

    def crawl_counter
      @redis.get("crawl-counter").to_i
    end
    def queue_counter
      @redis.get("queue-counter").to_i
    end
    def process_counter
      @redis.get("process-counter").to_i
    end

    private

    def status
      @stats.get_status
    end

    def print_counters
      logger.info counters
    end

    def counters
      "crawl_counter: #{crawl_counter} queue_counter: #{queue_counter} process_counter: #{process_counter} crawl_limit: #{@options[:crawl_limit]} currently_running: #{@redis.smembers("currently_running").count}"
    end

    # Sets the base url in redis.  If the first page is a redirect, it sets the base_url to the destination
    def set_base_url(redis)
      if redis.get("base_url").nil?
        unless !defined?(content.redirect_through) || content.redirect_through.empty? || !@options[:first_page_redirect_internal]
          uri = Addressable::URI.parse(content.redirect_through.last)
          redis.sadd("internal_urls", [uri.scheme, "://", uri.host, "/*"].join)
        end
        redis.set("base_url", content.url)
      end
    end

  end
end
