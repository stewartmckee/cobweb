
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
    
    # update the counters and then perform the get, returns false if we are outwith limits
    if @crawl.retrieve
    
      # if the crawled object is an object type we are interested
      if @crawl.content.permitted_type?
        
        # extract links from content and process them if we are still within queue limits (block will not run if we are outwith limits)
        @crawl.process_links do |link|

          # enqueue the links to resque
          puts "ENQUEUED LINK: #{link}"
          enqueue_content(content_request, link) 

        end
        
        
        if @crawl.to_be_processed?
          @crawl.process
          
          # enqueue to processing queue
          @crawl.redis.incr("crawl_job_enqueued_count")
          puts "ENQUEUED [#{@crawl.redis.get("crawl_job_enqueued_count")}] URL: #{@crawl.content.url}"
          send_to_processing_queue(@crawl.content.to_hash, content_request)
          
          
          #if the enqueue counter has been requested update that
          if content_request.has_key?(:enqueue_counter_key)
            enqueue_redis = Redis::Namespace.new(content_request[:enqueue_counter_namespace].to_s, :redis => Redis.new(content_request[:redis_options]))
            current_count = enqueue_redis.hget(content_request[:enqueue_counter_key], content_request[:enqueue_counter_field]).to_i
            enqueue_redis.hset(content_request[:enqueue_counter_key], content_request[:enqueue_counter_field], current_count+1)
          end
        else
          ap "@crawl.finished? #{@crawl.finished?}"
          ap "@crawl.within_crawl_limits? #{@crawl.within_crawl_limits?}"
          ap "@crawl.first_to_finish? #{@crawl.first_to_finish?}"
        end
      end
    end

    # test queue and crawl sizes to see if we have completed the crawl
    ap "finished? #{@crawl.finished?}"
    ap "first_to_finish? #{@crawl.first_to_finish?}" if @crawl.finished?
    if @crawl.finished? && @crawl.first_to_finish?
      finished(content_request)
    end
    
  end

  # Sets the crawl status to CobwebCrawlHelper::FINISHED and enqueues the crawl finished job
  def self.finished(content_request)
    additional_stats = {:crawl_id => content_request[:crawl_id], :crawled_base_url => @crawl.crawled_base_url}
    additional_stats[:redis_options] = content_request[:redis_options] unless content_request[:redis_options] == {}
    additional_stats[:source_id] = content_request[:source_id] unless content_request[:source_id].nil?
    
    @crawl.redis.incr("crawl_finished_enqueued_count")
    Resque.enqueue(const_get(content_request[:crawl_finished_queue]), @crawl.statistics.merge(additional_stats))
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
      Resque.enqueue(const_get(content_request[:processing_queue]), content_to_send)
    end
    puts "#{content_request[:url]} has been sent for processing. use_encoding_safe_process_job: #{content_request[:use_encoding_safe_process_job]}" if content_request[:debug]
  end

  private
  
  
  # Enqueues content to the crawl_job queue
  def self.enqueue_content(content_request, link)
    new_request = content_request.clone
    new_request[:url] = link
    new_request[:parent] = content_request[:url]
    #to help prevent accidentally double processing a link, let's mark it as queued just before the Resque.enqueue statement, rather than just after.
    Resque.enqueue(CrawlJob, new_request)
  end
  

end
