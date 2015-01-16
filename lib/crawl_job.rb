require 'cobweb/class_helper'
# CrawlJob defines a resque job to perform the crawl
class CrawlJob

  require "net/https"
  require "uri"
  require "redis"

  @queue = :cobweb_crawl_job

  # Resque perform method to maintain the crawl, enqueue found links and detect the end of crawl
  # content_request.keys =>
  #  [
  #   "crawl_id",
  #   "url",
  #   "processing_queue",
  #   "crawl_finished_queue",
  #   "internal_urls",
  #   "redis_options",
  #   "follow_redirects",
  #   "obey_robots",
  #   "debug",
  #   "started_at",
  #   "timeout",
  #   "raise_exceptions",
  #   "data",
  #   "cache",
  #   "respect_robots_delay",
  #   "store_response_codes",
  #   "direct_call_process_job",
  #   "store_inbound_links",
  #   "store_inbound_anchor_text",
  #   "store_image_attributes",
  #   "user_agent",
  #   "use_encoding_safe_process_job",
  #   "redirect_limit",
  #   "queue_system",
  #   "quiet",
  #   "cache_type",
  #   "external_urls",
  #   "seed_urls",
  #   "first_page_redirect_internal",
  #   "text_mime_types",
  #   "valid_mime_types",
  #   "proxy_addr",
  #   "proxy_port",
  #   "depth",
  #  ]

  def self.perform(content_request)
    # setup the crawl class to manage the crawl of this object
    @crawl = CobwebModule::Crawl.new(content_request)

    # update the counters and then perform the get, returns false if we are outwith limits
    if @crawl.retrieve

      # if the crawled object is an object type we are interested
      if @crawl.content.permitted_type?

        # moved the Process links from here to inside the to_be_processed loop.
        # extract links from content and process them if we are still within queue limits (block will not run if we are outwith limits)

        if @crawl.to_be_processed?

          queued_links_count = 0

          @crawl.process_links do |link|

            if @crawl.within_crawl_limits?
              # enqueue the links to resque
              # @crawl.logger.debug "QUEUE: #{link}"
              enqueue_content(content_request, link)
              queued_links_count += 1
            end

          end

          redirect_links = @crawl.redirect_links
          if Array(redirect_links).length > 0
            Array(redirect_links).each do |link|
              @crawl.redis.sadd "queued", link
              @crawl.increment_queue_counter
              enqueue_content(content_request, link)
              queued_links_count += 1
            end
          end

          @crawl.process do

            # enqueue to processing queue
            send_to_processing_queue(@crawl.content.to_hash, content_request)

            #if the enqueue counter has been requested update that
            if content_request.has_key?(:enqueue_counter_key)
              enqueue_redis = Redis::Namespace.new(content_request[:enqueue_counter_namespace].to_s, :redis => RedisConnection.new(content_request[:redis_options]))
              current_count = enqueue_redis.hget(content_request[:enqueue_counter_key], content_request[:enqueue_counter_field]).to_i
              enqueue_redis.hset(content_request[:enqueue_counter_key], content_request[:enqueue_counter_field], current_count+1)
            end

            if content_request[:store_response_codes]
              code_redis = Redis::Namespace.new("cobweb:#{content_request[:crawl_id]}", :redis => RedisConnection.new(content_request[:redis_options]))
              code_redis.hset("codes", Digest::MD5.hexdigest(content_request[:url]), @crawl.content.status_code)
            end

            last_depth = @crawl.redis.hget("depth", "#{Digest::MD5.hexdigest(content_request[:url])}")
            if last_depth.nil? || (last_depth > content_request[:depth])
              @crawl.redis.hset("depth", "#{Digest::MD5.hexdigest(content_request[:url])}", content_request[:depth])
            end

          end
          @crawl.store_graph_data

        else
          @crawl.logger.debug "@crawl.finished? #{@crawl.finished?}"
          @crawl.logger.debug "@crawl.within_crawl_limits? #{@crawl.within_crawl_limits?}"
          @crawl.logger.debug "@crawl.first_to_finish? #{@crawl.first_to_finish?}"
        end

      else
        @crawl.logger.warn "CrawlJob: Invalid MimeType #{content_request.inspect}"
      end
    else
      @crawl.logger.warn "CrawlJob: Retrieve returned FALSE"
    end

    @crawl.lock("finished") do
      # let the crawl know we're finished with this object
      @crawl.finished_processing

      # test queue and crawl sizes to see if we have completed the crawl
      if @crawl.finished?
        @crawl.logger.debug "Calling crawl_job finished"
        finished(content_request)
      end
    end
  end

  # Sets the crawl status to CobwebCrawlHelper::FINISHED and enqueues the crawl finished job
  def self.finished(content_request)
    additional_stats = {:crawl_id => content_request[:crawl_id], :crawled_base_url => @crawl.crawled_base_url, :data => content_request[:data]}
    additional_stats[:redis_options] = content_request[:redis_options] unless content_request[:redis_options] == {}
    additional_stats[:source_id] = content_request[:source_id] unless content_request[:source_id].nil?

    @crawl.finish

    @crawl.logger.debug "increment crawl_finished_enqueued_count from #{@crawl.redis.get("crawl_finished_enqueued_count")}"
    @crawl.redis.incr("crawl_finished_enqueued_count")
    Resque.enqueue(Cobweb::ClassHelper.resolve_class(content_request[:crawl_finished_queue]), @crawl.statistics.merge(additional_stats))
  end

  # Enqueues the content to the processing queue setup in options
  def self.send_to_processing_queue(content, content_request)
    content_to_send = content.merge({
      :depth => content_request[:depth],
      :internal_urls => content_request[:internal_urls],
      :redis_options => content_request[:redis_options],
      :source_id => content_request[:source_id],
      :crawl_id => content_request[:crawl_id],
      :data => content_request[:data]
    })
    if content_request[:direct_call_process_job]
      clazz = Cobweb::ClassHelper.resolve_class(content_request[:processing_queue])
      @crawl.logger.debug "PERFORM #{clazz.name} #{content_request[:url]}"
      clazz.perform(content_to_send)
    elsif content_request[:use_encoding_safe_process_job]
      content_to_send[:body] = Base64.encode64(content[:body])
      content_to_send[:processing_queue] = content_request[:processing_queue]
      @crawl.logger.debug "ENQUEUE EncodingSafeProcessJob #{content_request[:url]}"
      Resque.enqueue(EncodingSafeProcessJob, content_to_send)
    else
      clazz = Cobweb::ClassHelper.resolve_class(content_request[:processing_queue])
      @crawl.logger.debug "ENQUEUE #{clazz.name} #{content_request[:url]}"
      Resque.enqueue(clazz, content_to_send)
    end
  end

  private

  # Enqueues content to the crawl_job queue
  def self.enqueue_content(content_request, link)
    content_request.symbolize_keys!
    new_request = content_request.dup
    new_request[:url] = link
    new_request[:parent] = content_request[:url]
    new_request[:depth] = content_request[:depth].to_i + 1
    #to help prevent accidentally double processing a link, let's mark it as queued just before the Resque.enqueue statement, rather than just after.
    Resque.enqueue(CrawlJob, new_request)
  end

end