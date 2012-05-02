class Stats
  
  def initialize(options)
    @full_redis = Redis.new(options[:redis_options])
    @redis = NamespacedRedis.new(options[:redis_options], "cobweb-#{options[:crawl_id]}")
  end
  
  def start_crawl(options)
    unless @full_redis.sismember "cobweb_crawls", options[:crawl_id]
      @full_redis.sadd "cobweb_crawls", options[:crawl_id]
      options.keys.each do |key|
        @redis.hset "crawl_details", key, options[key]
      end
    end
    @redis.hset "statistics", "current_status", "Crawl Starting..."
  end
  
  def end_crawl(options)
    @full_redis.srem "cobweb_crawls", options[:crawl_id]
    @redis.hset "statistics", "current_status", "Crawl Stopped"
    @redis.del "crawl_details"
  end
  
  def update_statistics(content)
    
    crawl_counter = @redis.scard("crawled").to_i
    queue_counter = @redis.scard("queued").to_i
    
    if @redis.hexists "statistics", "average_response_time"
      @redis.hset("statistics", "average_response_time", (((@redis.hget("statistics", "average_response_time").to_f*crawl_counter) + content[:response_time].to_f) / (crawl_counter + 1)))
    else
      @redis.hset("statistics", "average_response_time", content[:response_time].to_f)
    end
    @redis.hset "statistics", "maximum_response_time", content[:response_time].to_f if @redis.hget("statistics", "maximum_response_time").nil? or content[:response_time].to_f > @redis.hget("statistics", "maximum_response_time").to_f
    @redis.hset "statistics", "minimum_response_time", content[:response_time].to_f if @redis.hget("statistics", "minimum_response_time").nil? or content[:response_time].to_f < @redis.hget("statistics", "minimum_response_time").to_f
    if @redis.hexists "statistics", "average_length"
      @redis.hset("statistics", "average_length", (((@redis.hget("statistics", "average_length").to_i*crawl_counter) + content[:length].to_i) / (crawl_counter + 1)))
    else
      @redis.hset("statistics", "average_length", content[:length].to_i)
    end
    @redis.hset "statistics", "maximum_length", content[:length].to_i if @redis.hget("statistics", "maximum_length").nil? or content[:length].to_i > @redis.hget("statistics", "maximum_length").to_i
    @redis.hset "statistics", "minimum_length", content[:length].to_i if @redis.hget("statistics", "minimum_length").nil? or content[:length].to_i < @redis.hget("statistics", "minimum_length").to_i
  
  
    if content[:mime_type].include?("text/html") or content[:mime_type].include?("application/xhtml+xml")
      @redis.hset "statistics", "page_count", @redis.hget("statistics", "page_count").to_i + 1
      @redis.hset "statistics", "page_size", @redis.hget("statistics", "page_size").to_i + content[:length].to_i
      increment_time_stat("pages_count")
    else
      @redis.hset "statistics", "asset_count", @redis.hget("statistics", "asset_count").to_i + 1
      @redis.hset "statistics", "asset_size", @redis.hget("statistics", "asset_size").to_i + content[:length].to_i
      increment_time_stat("assets_count")
    end
    
    total_redirects = @redis.hget("statistics", "total_redirects").to_i
    @redis.hset "statistics", "total_redirects", 0 if total_redirects.nil?
    @redis.hset("statistics", "total_redirects", total_redirects += content[:redirect_through].count) unless content[:redirect_through].nil?

    @redis.hset "statistics", "crawl_counter", crawl_counter
    @redis.hset "statistics", "queue_counter", queue_counter
    
    total_length = @redis.hget("statistics", "total_length").to_i
    @redis.hset "statistics", "total_length", total_length + content[:length].to_i

    mime_counts = {}
    if @redis.hexists "statistics", "mime_counts"
      mime_counts = JSON.parse(@redis.hget("statistics", "mime_counts"))
      if mime_counts.has_key? content[:mime_type]
        mime_counts[content[:mime_type]] += 1
      else
        mime_counts[content[:mime_type]] = 1
      end
    else
      mime_counts = {content[:mime_type] => 1}
    end
    @redis.hset "statistics", "mime_counts", mime_counts.to_json

    # record mime categories stats
    if content[:mime_type].starts_with? "text"
      increment_time_stat("mime_text_count")
    elsif content[:mime_type].starts_with? "application"
      increment_time_stat("mime_application_count")
    elsif content[:mime_type].starts_with? "audio"
      increment_time_stat("mime_audio_count")
    elsif content[:mime_type].starts_with? "image"
      increment_time_stat("mime_image_count")
    elsif content[:mime_type].starts_with? "message"
      increment_time_stat("mime_message_count")
    elsif content[:mime_type].starts_with? "model"
      increment_time_stat("mime_model_count")
    elsif content[:mime_type].starts_with? "multipart"
      increment_time_stat("mime_multipart_count")
    elsif content[:mime_type].starts_with? "video"
      increment_time_stat("mime_video_count")
    end
    
    status_counts = {}
    if @redis.hexists "statistics", "status_counts"
      status_counts = HashUtil.deep_symbolize_keys(JSON.parse(@redis.hget("statistics", "status_counts")))
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
    
    @redis.hset "statistics", "status_counts", status_counts.to_json
    
    
    ## time based statistics
    increment_time_stat("minute_totals", "minute", 60)    
    
    get_statistics
  end
  
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
  
  def get_statistics
    
    @statistics = HashUtil.deep_symbolize_keys(@redis.hgetall("statistics"))
    if @statistics[:status_counts].nil?
      @statistics[:status_counts]
    else
      @statistics[:status_counts] = JSON.parse(@statistics[:status_counts])
    end
    if @statistics[:mime_counts].nil?
      @statistics[:mime_counts]
    else
      @statistics[:mime_counts] = JSON.parse(@statistics[:mime_counts])
    end
    @statistics
  end
  
  def update_status(status)
    @redis.hset "statistics", "current_status", status
  end
  
  def get_status
    @redis.hget "statistics", "current_status"
  end
  
  def set_totals
    stats = get_statistics
    stats[:crawled] = @redis.smembers "crawled"
  end
  
end


