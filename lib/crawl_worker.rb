require File.expand_path(File.dirname(__FILE__) + '/cobweb')
require File.expand_path(File.dirname(__FILE__) + '/sidekiq/cobweb_helper')

# If your client is single-threaded, we just need a single connection in our Redis connection pool
#Sidekiq.configure_client do |config|
#  config.redis = { :namespace => 'x', :size => 1, :url => 'redis://localhost:6379/14' }
#end

# Sidekiq server is multi-threaded so our Redis connection pool size defaults to concurrency (-c)
#Sidekiq.configure_server do |config|
#  config.redis = { :namespace => 'x', :url => 'redis://localhost:6379/14' }
#end

class CrawlWorker
  include Sidekiq::Worker
  sidekiq_options :queue => "crawl_worker", :retry => false if SIDEKIQ_INSTALLED
  
  def perform(content_request)
    puts "Performing for #{content_request["url"]}"
    # setup the crawl class to manage the crawl of this object
    @crawl = CobwebModule::Crawl.new(content_request)
    
    # update the counters and then perform the get, returns false if we are outwith limits
    if @crawl.retrieve
    
      # if the crawled object is an object type we are interested
      if @crawl.content.permitted_type?
                
        # extract links from content and process them if we are still within queue limits (block will not run if we are outwith limits)
        @crawl.process_links do |link|
          @crawl.lock("queue_links") do
            if @crawl.within_crawl_limits? && !@crawl.already_handled?(link)
              # enqueue the links to sidekiq
              @crawl.debug_puts "QUEUED LINK: #{link}" 
              enqueue_content(content_request, link)
            end
          end
        end
        
        if @crawl.to_be_processed?
          
          @crawl.process do

            # enqueue to processing queue
            @crawl.debug_puts "SENT FOR PROCESSING [#{@crawl.redis.get("crawl_job_enqueued_count")}] URL: #{@crawl.content.url}"
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
        
      end
    end
    
    #@crawl.lock("finished") do
      # let the crawl know we're finished with this object
      @crawl.finished_processing

      # test queue and crawl sizes to see if we have completed the crawl
      @crawl.debug_puts "finished? #{@crawl.finished?}"
      if @crawl.finished?
        @crawl.debug_puts "Calling crawl_job finished"
        finished(content_request)
      end
    #end
  end
  def self.jobs
    Sidekiq.redis do |conn|
      conn.smembers(get_sidekiq_options[:queue]).count
    end
  end
  

    # Sets the crawl status to CobwebCrawlHelper::FINISHED and enqueues the crawl finished job
  def finished(content_request)
    additional_stats = {:crawl_id => content_request[:crawl_id], :crawled_base_url => @crawl.crawled_base_url}
    additional_stats[:redis_options] = content_request[:redis_options] unless content_request[:redis_options] == {}
    additional_stats[:source_id] = content_request[:source_id] unless content_request[:source_id].nil?

    @crawl.finish

    @crawl.debug_puts "increment crawl_finished_enqueued_count"
    @crawl.redis.incr("crawl_finished_enqueued_count")
    content_request[:crawl_finished_queue].constantize.perform_async(@crawl.statistics.merge(additional_stats))
  end
  
  # Enqueues the content to the processing queue setup in options
  def send_to_processing_queue(content, content_request)
    content_to_send = content.merge({:internal_urls => content_request[:internal_urls], :redis_options => content_request[:redis_options], :source_id => content_request[:source_id], :crawl_id => content_request[:crawl_id]})
    content_to_send.keys.each do |key|
      content_to_send[key] = content_to_send[key].force_encoding('UTF-8') if content_to_send[key].kind_of?(String)
    end
    if content_request[:direct_call_process_job]
      clazz = content_request[:processing_queue].constantize
      clazz.perform(content_to_send)
    else
      content_request[:processing_queue].constantize.perform_async(content_to_send)
    end
    @crawl.debug_puts "#{content_request[:url]} has been sent for processing. use_encoding_safe_process_job: #{content_request[:use_encoding_safe_process_job]}"
  end

  private
  
  # Enqueues content to the crawl_job queue
  def enqueue_content(content_request, link)
    new_request = content_request.clone
    new_request[:url] = link
    new_request[:parent] = content_request[:url]
    CrawlWorker.perform_async(new_request)
  end

end