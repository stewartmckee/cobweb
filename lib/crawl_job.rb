
# CrawlJob defines a resque job to perform the crawl
class CrawlJob
  
  require "net/https"  
  require "uri"
  require "redis"
  
  @queue = :cobweb_crawl_job
  
  # Resque perform method to maintain the crawl, enqueue found links and detect the end of crawl
  def self.perform(content_request)
    # setup the crawl class to manage the crawl of this object
    @crawl = CobwebModule::Crawl.new(content_request)

    @crawl.debug_puts(content_request[:url])
    
    # update the counters and then perform the get, returns false if we are outwith limits
    if @crawl.retrieve
      @crawl.debug_puts "In Retrieve"

    
      # if the crawled object is an object type we are interested
      if @crawl.content.permitted_type?
        
        # moved the Process links from here to inside the to_be_processed loop.  
          # extract links from content and process them if we are still within queue limits (block will not run if we are outwith limits)

        if @crawl.to_be_processed?
          
          @crawl.process do

            # enqueue to processing queue
            @crawl.debug_puts "ENQUEUED [#{@crawl.redis.get("crawl_job_enqueued_count")}] URL: #{@crawl.content.url}"
            send_to_processing_queue(@crawl.content.to_hash, content_request)

            #if the enqueue counter has been requested update that
            if content_request.has_key?(:enqueue_counter_key)
              enqueue_redis = Redis::Namespace.new(content_request[:enqueue_counter_namespace].to_s, :redis => RedisConnection.new(content_request[:redis_options]))
              current_count = enqueue_redis.hget(content_request[:enqueue_counter_key], content_request[:enqueue_counter_field]).to_i
              enqueue_redis.hset(content_request[:enqueue_counter_key], content_request[:enqueue_counter_field], current_count+1)
            end
            
          end
        else
          @crawl.debug_puts "@crawl.finished? #{@crawl.finished?}"
          @crawl.debug_puts "@crawl.within_crawl_limits? #{@crawl.within_crawl_limits?}"
          @crawl.debug_puts "@crawl.first_to_finish? #{@crawl.first_to_finish?}"
        end

        @crawl.logger.debug  "Completed Queueing"

        @crawl.process_links do |link|

          if @crawl.within_crawl_limits?
            # enqueue the links to resque
            @crawl.logger.info "Queueing Link: #{link}"
            enqueue_content(content_request, link)
          end

        end
        
      else 
        @crawl.logger.warn "Invalid MimeType"
      end 
    else 
      @crawl.logger.warn "Retrieve returned FALSE #{content_request[:url]}"
    end
    
    @crawl.lock("finished") do
      # let the crawl know we're finished with this object
      @crawl.finished_processing

      # test queue and crawl sizes to see if we have completed the crawl
      @crawl.debug_puts "finished? #{@crawl.finished?}"
      if @crawl.finished?
        @crawl.debug_puts "Calling crawl_job finished"
        finished(content_request)
      end
    end
    
  end

  # Sets the crawl status to CobwebCrawlHelper::FINISHED and enqueues the crawl finished job
  def self.finished(content_request)
    additional_stats = {:crawl_id => content_request[:crawl_id], :crawled_base_url => @crawl.crawled_base_url}
    additional_stats[:redis_options] = content_request[:redis_options] unless content_request[:redis_options] == {}
    additional_stats[:source_id] = content_request[:source_id] unless content_request[:source_id].nil?
    
    @crawl.finish

    @crawl.debug_puts "increment crawl_finished_enqueued_count from #{@crawl.redis.get("crawl_finished_enqueued_count")}"
    @crawl.redis.incr("crawl_finished_enqueued_count")
    Resque.enqueue(const_get(content_request[:crawl_finished_queue]), @crawl.statistics.merge(additional_stats))
  end
  
  # Enqueues the content to the processing queue setup in options
  def self.send_to_processing_queue(content, content_request)
    content_to_send = content.merge({:depth => content_request[:depth], :internal_urls => content_request[:internal_urls], :redis_options => content_request[:redis_options], :source_id => content_request[:source_id], :crawl_id => content_request[:crawl_id]})
    if content_request[:direct_call_process_job]
      #clazz = content_request[:processing_queue].to_s.constantize
      clazz = const_get(content_request[:processing_queue])
      clazz.perform(content_to_send)
    elsif content_request[:use_encoding_safe_process_job]
      content_to_send[:body] = Base64.encode64(content[:body])
      content_to_send[:processing_queue] = content_request[:processing_queue]
      Resque.enqueue(EncodingSafeProcessJob, content_to_send)
    else
      Resque.enqueue(const_get(content_request[:processing_queue]), content_to_send)
    end
    @crawl.logger.debug "#{content_request[:url]} has been sent for processing. use_encoding_safe_process_job: #{content_request[:use_encoding_safe_process_job]}"
  end

  private
  
  # Enqueues content to the crawl_job queue
  def self.enqueue_content(content_request, link)
    new_request = content_request.clone
    new_request[:url] = link
    new_request[:parent] = content_request[:url]
    new_request[:depth] = 0 
    new_request[:depth] = content_request["depth"].to_i + 1
    #to help prevent accidentally double processing a link, let's mark it as queued just before the Resque.enqueue statement, rather than just after.
    Resque.enqueue(CrawlJob, new_request)
  end

end