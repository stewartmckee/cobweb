require 'sinatra'
require 'haml'

class Stats < Sinatra::Base
  
  def self.update_statistics(statistics)
    @@statistics = statistics
    @@statistics
  end
  
  def self.get_statistics
    @@statistics ||= {}
  end
  
  def self.update_status(status)
    @@status = status
  end
  
  def self.set_totals
    stats = @redis.hgetall "statistics"
    stats[:total_pages] = @redis.get("total_pages").to_i
    stats[:total_assets] = @redis.get("total_assets").to_i
    stats[:crawl_counter] = @crawl_counter
    stats[:queue_counter] = @queue_counter
    stats[:crawled] = @redis.smembers "crawled"

    Stats.update_statistics(stats)
  end
  
  def self.set_statistics_in_redis(redis, content)
    
    @redis = redis
    
    crawl_counter = redis.get("crawl-counter").to_i
    queue_counter = redis.get("queue-counter").to_i
    
    if redis.hexists "statistics", "average_response_time"
      redis.hset("statistics", "average_response_time", (((redis.hget("statistics", "average_response_time").to_f*crawl_counter) + content[:response_time].to_f) / (crawl_counter + 1)))
    else
      redis.hset("statistics", "average_response_time", content[:response_time].to_f)
    end
    redis.hset "statistics", "maximum_response_time", content[:response_time].to_f if redis.hget("statistics", "maximum_response_time").nil? or content[:response_time].to_f > redis.hget("statistics", "maximum_response_time").to_f
    redis.hset "statistics", "minimum_response_time", content[:response_time].to_f if redis.hget("statistics", "minimum_response_time").nil? or content[:response_time].to_f < redis.hget("statistics", "minimum_response_time").to_f
    if redis.hexists "statistics", "average_length"
      redis.hset("statistics", "average_length", (((redis.hget("statistics", "average_length").to_i*crawl_counter) + content[:length].to_i) / (crawl_counter + 1)))
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
    
    @@statistics = @redis.hgetall "statistics"
  end
  
  set :views, settings.root + '/../views'
  
  get '/' do
    @statistics = @@statistics
    @status = @@status
    haml :statistics
  end
  
  def self.start
    thread = Thread.new do
      Stats.run!

      ## we need to manually kill the main thread as sinatra traps the interrupts
      Thread.main.kill
    end    
  end
end


