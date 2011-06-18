class CrawlJob
  
  require "net/https"  
  require "uri"
  require "redis"

  @queue = :cobweb_crawl_job

  ## redis params used
  #
  # crawl-counter
  # crawled
  # queue-counter
  # statistics[:average_response_time]
  # statistics[:maximum_response_time]
  # statistics[:minimum_response_time]
  # statistics[:average_length]
  # statistics[:maximum_length]
  # statistics[:minimum_length]
  # statistics[:queued_at]
  # statistics[:started_at]
  # statistics]:finished_at]
  # total_pages
  # total_assets
  # statistics[:mime_counts]["mime_type"]
  # statistics[:status_counts][xxx]

  def self.perform(content_request)
    # change all hash keys to symbols    
    content_request.deep_symbolize_keys
    redis = NamespacedRedis.new(Redis.new(content_request[:redis_options]), "cobweb-#{content_request[:crawl_id]}")
    @absolutize = Absolutize.new(content_request[:url], :output_debug => false, :raise_exceptions => false, :force_escaping => false, :remove_anchors => true)

    # check we haven't crawled this url before
    unless redis.sismember "crawled", content_request[:url]
      
      # increment counter and check we haven't hit our crawl limit
      redis.incr "crawl-counter"
      crawl_counter = redis.get("crawl-counter").to_i
      queue_counter = redis.get("queue-counter").to_i
      if crawl_counter <= content_request[:crawl_limit].to_i
        content = CobWeb.new(content_request).get(content_request[:url])

        ## update statistics
        if redis.hexists "statistics", "average_response_time"
          redis.hset("statistics", "average_response_time", (((redis.hget("statistics", "average_response_time").to_f*crawl_counter) + content[:response_time].to_f) / crawl_counter + 1))
        else
          redis.hset("statistics", "average_response_time", content[:response_time].to_f)
        end
        redis.hset "statistics", "maximum_response_time", content[:response_time].to_f if redis.hget("statistics", "maximum_response_time").nil? or content[:response_time].to_f > redis.hget("statistics", "maximum_response_time").to_f
        redis.hset "statistics", "minimum_response_time", content[:response_time].to_f if redis.hget("statistics", "minimum_response_time").nil? or content[:response_time].to_f < redis.hget("statistics", "minimum_response_time").to_f
        if redis.hexists "statistics", "average_length"
          redis.hset("statistics", "average_length", (((redis.hget("statistics", "average_length").to_i*crawl_counter) + content[:length].to_i) / crawl_counter + 1))
        else
          redis.hset("statistics", "average_length", content[:length].to_i)
        end
        redis.hset "statistics", "maximum_length", content[:length].to_i if redis.hget("statistics", "maximum_length").nil? or content[:length].to_i > redis.hget("statistics", "maximum_length").to_i
        redis.hset "statistics", "minimum_length", content[:length].to_i if redis.hget("statistics", "minimum_length").nil? or content[:length].to_i < redis.hget("statistics", "minimum_length").to_i

        if content[:mime_type].include?("text/html") or content[:mime_type].include?("application/xhtml+xml")
          redis.incr "total_pages"
        else
          redis.incr "total_assets"
        end

        mime_counts = {}
        if redis.hexists "statistics", "mime_counts"
          mime_counts = JSON.parse(redis.hget("statistics", "mime_counts"))
          if mime_counts.has_key? content[:mime_type]
            mime_counts[content[:mime_type]] += 1
          else
            mime_counts[content[:mime_type]] = 1
          end
        else
          mime_counts = {content[:mime_type] => 1}
        end
        redis.hset "statistics", "mime_counts", mime_counts.to_json

        status_counts = {}
        if redis.hexists "statistics", "status_counts"
          status_counts = JSON.parse(redis.hget("statistics", "status_counts"))
          if status_counts.has_key? content[:status_code].to_i
            status_counts[content[:status_code].to_i] += 1
          else
            status_counts[content[:status_code].to_i] = 1
          end
        else
          status_counts = {content[:status_code].to_i => 1}
        end
        redis.hset "statistics", "status_counts", status_counts.to_json

        redis.sadd "crawled", content_request[:url]
        set_base_url redis, content, content_request[:base_url]
        content[:links].keys.map{|key| content[:links][key]}.flatten.each do |link|
          unless redis.sismember "crawled", link
            puts "Checking if #{link} matches #{redis.get("base_url")} as internal?" if content_request[:debug]
            if link.to_s.match(Regexp.new("^#{redis.get("base_url")}"))
              puts "Matched as #{link} as internal"
              if queue_counter <= content_request[:crawl_limit].to_i
                new_request = content_request.clone
                new_request[:url] = link
                new_request[:parent] = content_request[:url]
                Resque.enqueue(CrawlJob, new_request)
                redis.incr "queue-counter"
                queue_counter += 1
              end
            end
          end
        end

        # enqueue to processing queue
        Resque.enqueue(const_get(content_request[:processing_queue]), content.merge({:source_id => content_request[:source_id]}))
        puts "#{content_request[:url]} has been sent for processing." if content_request[:debug]
        puts "Crawled: #{crawl_counter} Limit: #{content_request[:crawl_limit]} Queued: #{queue_counter}" if content_request[:debug]


      else
        puts "Crawl Limit Exceeded by #{crawl_counter - content_request[:crawl_limit].to_i} objects" if content_request[:debug]
      end
    else
      puts "Already crawled #{content_request[:url]}" if content_request[:debug]
    end

    # detect finished state

    if queue_counter == crawl_counter or content_request[:crawl_limit].to_i <= queue_counter 
     
      puts "queue_counter: #{queue_counter}"
      puts "crawl_counter: #{crawl_counter}"
      puts "crawl_limit: #{content_request[:crawl_limit]}"

      # finished
      puts "FINISHED"
      stats = redis.hgetall "statistics"
      stats[:total_pages] = redis.get "total_pages"
      stats[:total_assets] = redis.get "total_assets"
      stats[:crawl_counter] = redis.get "crawl_counter"
      stats[:queue_counter] = redis.get "queue_counter"
      stats[:crawled] = redis.smembers "crawled"
      
      Resque.enqueue(const_get(content_request[:crawl_finished_queue]), stats.merge({:source_id => content_request[:source_id]}))      
      
      ap stats
    end
  end

  private
  def self.set_base_url(redis, content, base_url)
    if redis.get("base_url").nil?
      if content[:status_code] >= 300 and content[:status_code] < 400
        #redirect received for first url
        redis.set("base_url", @absolutize.url(content[:location]).to_s)
        puts "WARNING: base_url given redirects to another location, setting base_url to #{@absolutize.url(content[:location]).to_s}"
      else
        redis.set("base_url", base_url)
      end
    end
  end

  
end
