# Stats class is the main statisitics hub for monitoring crawls.  Either can be viewed through the Sinatra interface, or returned from the CobwebCrawler.crawl method or block
class Stats
  require 'json'
  
  attr_reader :redis
  
  # Sets up redis usage for statistics
  def initialize(options)
    options[:redis_options] = {} unless options.has_key? :redis_options
    if options[:redis]
      @full_redis = options[:redis]
    else
      @full_redis = Redis.new(options[:redis_options])
    end
    @lock = Mutex.new
    @redis = Redis::Namespace.new("cobweb-#{Cobweb.version}-#{options[:crawl_id]}", :redis => @full_redis)
  end
  
  # Sets up the crawl in statistics
  def start_crawl(options)
    unless @full_redis.sismember "cobweb_crawls", options[:crawl_id]
      @full_redis.sadd "cobweb_crawls", options[:crawl_id]
      options.keys.each do |key|
        @redis.hset "crawl_details", key, options[key].to_s
      end
    end
    @redis.hset "statistics", "crawl_started_at", DateTime.now
    @redis.hset "statistics", "current_status", CobwebCrawlHelper::STARTING
  end
  
  # Removes the crawl from the running crawls and updates status
  def end_crawl(options, cancelled=false)
    #@full_redis.srem "cobweb_crawls", options[:crawl_id]
    if cancelled
      @redis.hset "statistics", "current_status", CobwebCrawlHelper::CANCELLED
    else
      @redis.hset "statistics", "current_status", CobwebCrawlHelper::FINISHED
    end
    @redis.hset "statistics", "crawl_finished_at", DateTime.now
    #@redis.del "crawl_details"
  end
  
  def get_crawled
    @redis.smembers "crawled"
  end

  def inbound_links_for(url)
    uri = UriHelper.parse(url)
    @redis.smembers("inbound_links_#{Digest::MD5.hexdigest(uri.to_s)}")
  end

  # Returns statistics hash.  update_statistics takes the content hash, extracts statistics from it and updates redis with the data.  
  def update_statistics(content, crawl_counter=@redis.scard("crawled").to_i, queue_counter=@redis.scard("queued").to_i)
    @lock.synchronize {
      @statistics = get_statistics
      
      if @statistics.has_key? :average_response_time
        @statistics[:average_response_time] = (((@redis.hget("statistics", "average_response_time").to_f*crawl_counter) + content[:response_time].to_f) / (crawl_counter + 1))
      else
        @statistics[:average_response_time] = content[:response_time].to_f
      end
      @statistics[:maximum_response_time] = content[:response_time].to_f if @statistics[:maximum_response_time].nil? or content[:response_time].to_f > @statistics[:maximum_response_time].to_f
      @statistics[:minimum_response_time] = content[:response_time].to_f if @statistics[:minimum_response_time].nil? or content[:response_time].to_f < @statistics[:minimum_response_time].to_f
      if @statistics.has_key? :average_length
        @statistics[:average_length] = (((@redis.hget("statistics", "average_length").to_i*crawl_counter) + content[:length].to_i) / (crawl_counter + 1))
      else
        @statistics[:average_length] = content[:length].to_i
      end
      @statistics[:maximum_length] = content[:length].to_i if @redis.hget("statistics", "maximum_length").nil? or content[:length].to_i > @statistics[:maximum_length].to_i
      @statistics[:minimum_length] = content[:length].to_i if @redis.hget("statistics", "minimum_length").nil? or content[:length].to_i < @statistics[:minimum_length].to_i
      
      if content[:mime_type].include?("text/html") or content[:mime_type].include?("application/xhtml+xml")
        @statistics[:page_count] = @statistics[:page_count].to_i + 1
        @statistics[:page_size] = @statistics[:page_size].to_i + content[:length].to_i
        increment_time_stat("pages_count")
      else
        @statistics[:asset_count] = @statistics[:asset_count].to_i + 1
        @statistics[:asset_size] = @statistics[:asset_size].to_i + content[:length].to_i
        increment_time_stat("assets_count")
      end
      
      total_redirects = @statistics[:total_redirects].to_i
      @statistics[:total_redirects] = 0 if total_redirects.nil?
      @statistics[:total_redirects] = total_redirects += content[:redirect_through].count unless content[:redirect_through].nil?

      @statistics[:crawl_counter] = crawl_counter
      @statistics[:queue_counter] = queue_counter
      
      total_length = @statistics[:total_length].to_i
      @statistics[:total_length] = total_length + content[:length].to_i

      mime_counts = {}
      if @statistics.has_key? :mime_counts
        mime_counts = @statistics[:mime_counts]
        if mime_counts.has_key? content[:mime_type]
          mime_counts[content[:mime_type]] += 1
        else
          mime_counts[content[:mime_type]] = 1
        end
      else
        mime_counts = {content[:mime_type] => 1}
      end

      @statistics[:mime_counts] = mime_counts.to_json

      # record mime categories stats
      if content[:mime_type].cobweb_starts_with? "text"
        increment_time_stat("mime_text_count")
      elsif content[:mime_type].cobweb_starts_with? "application"
        increment_time_stat("mime_application_count")
      elsif content[:mime_type].cobweb_starts_with? "audio"
        increment_time_stat("mime_audio_count")
      elsif content[:mime_type].cobweb_starts_with? "image"
        increment_time_stat("mime_image_count")
      elsif content[:mime_type].cobweb_starts_with? "message"
        increment_time_stat("mime_message_count")
      elsif content[:mime_type].cobweb_starts_with? "model"
        increment_time_stat("mime_model_count")
      elsif content[:mime_type].cobweb_starts_with? "multipart"
        increment_time_stat("mime_multipart_count")
      elsif content[:mime_type].cobweb_starts_with? "video"
        increment_time_stat("mime_video_count")
      end
      
      status_counts = {}
      if @statistics.has_key? :status_counts
        status_counts = @statistics[:status_counts]
        status_code = content[:status_code].to_i.to_s.to_sym
        if status_counts.has_key? status_code
          status_counts[status_code] += 1
        else
          status_counts[status_code] = 1
        end      
      else
        status_counts = {status_code => 1}
      end
      
      # record statistics by status type
      if content[:status_code] >= 200 && content[:status_code] < 300
        increment_time_stat("status_200_count")
      elsif content[:status_code] >= 400 && content[:status_code] < 500
        increment_time_stat("status|_400_count")
      elsif content[:status_code] >= 500 && content[:status_code] < 600
        increment_time_stat("status|_500_count")
      end
      
      @statistics[:status_counts] = status_counts.to_json
      
      ## time based statistics
      increment_time_stat("minute_totals", "minute", 60)
      
      redis_command = "@redis.hmset 'statistics', #{@statistics.keys.map{|key| "'#{key}', '#{@statistics[key].to_s.gsub("'","''")}'"}.join(", ")}"
      instance_eval redis_command
    }
    @statistics
  end
  
  # Returns the statistics hash
  def get_statistics
    
    statistics = HashUtil.deep_symbolize_keys(@redis.hgetall("statistics"))
    if statistics[:status_counts].nil?
      statistics[:status_counts]
    else
      statistics[:status_counts] = JSON.parse(statistics[:status_counts])
    end
    if statistics[:mime_counts].nil?
      statistics[:mime_counts]
    else
      statistics[:mime_counts] = JSON.parse(statistics[:mime_counts])
    end
    statistics
  end
  
  # Sets the current status of the crawl
  def update_status(status)
    @redis.hset("statistics", "current_status", status) unless get_status == CobwebCrawlHelper::CANCELLED
  end
  
  # Returns the current status of the crawl
  def get_status
    @redis.hget "statistics", "current_status"
  end
  
  # Sets totals for the end of the crawl (Not Used)
  def set_totals
    stats = get_statistics
    stats[:crawled] = @redis.smembers "crawled"
  end
  
  private
  # Records a time based statistic
  def record_time_stat(stat_name, value, type="minute", duration=60)
    key = DateTime.now.strftime("%Y-%m-%d %H:%M")
    if type == "hour"
      key = DateTime.now.strftime("%Y-%m-%d %H:00")
    end
    stat_value = @redis.hget(stat_name, key).to_i
    stat_count = @redis.hget("#{stat_name}-count", key).to_i
    
    if minute_count.nil?
      @redis.hset stat_name, key, value
      @redis.hset "#{stat_name}-count", key, 1
    else
      @redis.hset stat_name, key, ((stat_value*stat_count) + value) / (stat_count+1)
      @redis.hset "#{stat_name}-count", key, stat_count+1
    end
  end
  
  # Increments a time based statistic (eg pages per minute)
  def increment_time_stat(stat_name, type="minute", duration=60)
    key = DateTime.now.strftime("%Y-%m-%d %H:%M")
    if type == "hour"
      key = DateTime.now.strftime("%Y-%m-%d %H:00")
    end
    minute_count = @redis.hget(stat_name, key).to_i
    if minute_count.nil?
      @redis.hset stat_name, key, 1
    else
      @redis.hset stat_name, key, minute_count + 1
    end
    #clear up older data
    @redis.hgetall(stat_name).keys.each do |key|
      if DateTime.parse(key) < DateTime.now-(duration/1440.0)
        puts "Deleting #{stat_name} - #{key}"
        @redis.hdel(stat_name, key)
      end
    end
  end
  
end


