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
    n = 0
    debug = true
    # update the counters and then perform the get, returns false if we are outwith limits
    retreived = false

    # can't retreive for too long
    retreived = @crawl.retrieve

    if retreived
      queued_links_count = 0
      # following redirects
      if @crawl.redirect_links.present?
        redirect_links = @crawl.redirect_links
        if Array(redirect_links).length > 0
          Array(redirect_links).each do |link|
            full_link = UriHelper.join_no_fragment(content_request[:url], link.to_s)
            new_link = full_link.to_s
            unless @crawl.already_handled?(new_link) # don't queue something already queued
              @crawl.redis.sadd "queued", new_link
              @crawl.increment_queue_counter
              enqueue_content(content_request, new_link)
              queued_links_count += 1
            end
          end
        end

      # if the crawled object is an object type we are interested
      elsif @crawl.content.permitted_type?
        # moved the Process links from here to inside the to_be_processed loop.
        # extract links from content and process them if we are still within queue limits (block will not run if we are outwith limits)

        if @crawl.to_be_processed?

          # process the links we find on the page, queueing them for crawls if they are ready
          @crawl.document_links.uniq.each do |doc_link|
            if @crawl.cobweb_links.internal?(doc_link) && !@crawl.already_handled?(doc_link)
              enqueue_content(content_request, doc_link)
              queued_links_count += 1
            end
          end

          # send the document to be page processed
          @crawl.process do
            # enqueue to processing queue
            send_to_processing_queue(@crawl.content.to_hash, content_request)
          end

        else
          @crawl.logger.debug "Crawler::CrawlJob Crawl:#{content_request[:crawl_id]} @crawl.finished? #{@crawl.finished?}"
          @crawl.logger.debug "Crawler::CrawlJob Crawl:#{content_request[:crawl_id]} @crawl.within_crawl_limits? #{@crawl.within_crawl_limits?}"
          @crawl.logger.debug "Crawler::CrawlJob Crawl:#{content_request[:crawl_id]} @crawl.first_to_finish? #{@crawl.first_to_finish?}"
        end
      else
        @crawl.logger.warn "Crawler::CrawlJob Crawl:#{content_request[:crawl_id]} Invalid RetrievedContentInvalidMimeType #{content_request[:url]}"
      end
    else
      @crawl.logger.warn "Crawler::CrawlJob Crawl:#{content_request[:crawl_id]} NotRetrievedUrl #{content_request[:url]}"
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
      :parent => content_request[:parent],
      :depth => content_request[:depth],
      :internal_urls => content_request[:internal_urls],
      :redis_options => content_request[:redis_options],
      :source_id => content_request[:source_id],
      :crawl_id => content_request[:crawl_id],
      :data => content_request[:data]
    })

    if content_request[:direct_call_process_job]
      clazz = Cobweb::ClassHelper.resolve_class(content_request[:processing_queue])
      @crawl.logger.debug "Crawler::CrawlJob #{clazz.name}.perform Crawl:#{content_to_send[:crawl_id]} Url:#{content_request[:url]}"
      clazz.perform(content_to_send)
    elsif content_request[:use_encoding_safe_process_job]
      content_to_send[:body] = Base64.encode64(content[:body])
      content_to_send[:processing_queue] = content_request[:processing_queue]
      @crawl.logger.debug "Crawler::CrawlJob ENQUEUE EncodingSafeProcessJob Crawl:#{content_to_send[:crawl_id]} Url:#{content_request[:url]}"
      Resque.enqueue(EncodingSafeProcessJob, content_to_send)
    else
      clazz = Cobweb::ClassHelper.resolve_class(content_request[:processing_queue])
      @crawl.logger.debug "Crawler::CrawlJob ENQUEUE #{clazz.name} Crawl:#{content_to_send[:crawl_id]} Url:#{content_request[:url]}"
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
    res = Resque.enqueue(CrawlJob, new_request)
    @crawl.logger.debug "Crawler::CrawlJob Crawl:#{content_request[:crawl_id]} depth:#{new_request[:depth]} Url:#{new_request[:parent]} -> Url:#{new_request[:url]}"
  end

end
