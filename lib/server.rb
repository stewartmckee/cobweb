require 'sinatra'
require 'haml'

# Sinatra server to host the statistics for the CobwebCrawler
class Server < Sinatra::Base

  set :views, settings.root + '/../views'
  set :public_folder, settings.root + '/../public'
  enable :static
  
  # Sinatra Dashboard
  get '/' do
    @full_redis = Redis.new
    
    @colors = ["#00366f", "#006ba0", "#3F0BDB", "#396CB3"]
    
    @crawls = []
    @full_redis.smembers("cobweb_crawls").each do |crawl_id|
      redis = NamespacedRedis.new({}, "cobweb-#{Cobweb.version}-#{crawl_id}")
      stats = HashUtil.deep_symbolize_keys({
        :crawl_details => redis.hgetall("crawl_details"), 
        :statistics => redis.hgetall("statistics"),
        :minute_totals => redis.hgetall("minute_totals")
        })
      @crawls << stats
    end
    
    haml :home
  end
  
  # Sinatra Crawl Detail
  get '/statistics/:crawl_id' do
    redis = NamespacedRedis.new({}, "cobweb-#{Cobweb.version}-#{params[:crawl_id]}")
    
    @statistics = HashUtil.deep_symbolize_keys(redis.hgetall("statistics"))
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
    @crawl = {
        :statistics => @statistics,
        :crawl_details => HashUtil.deep_symbolize_keys(redis.hgetall("crawl_details")), 
        :minute_totals => HashUtil.deep_symbolize_keys(redis.hgetall("minute_totals")),
        :status_200_count => HashUtil.deep_symbolize_keys(redis.hgetall("status_200_count")),
        :status_400_count => HashUtil.deep_symbolize_keys(redis.hgetall("status_400_count")),
        :status_500_count => HashUtil.deep_symbolize_keys(redis.hgetall("status_500_count")),
        :mime_text_count => HashUtil.deep_symbolize_keys(redis.hgetall("mime_text_count")),
        :mime_image_count => HashUtil.deep_symbolize_keys(redis.hgetall("mime_image_count")),
        :mime_application_count => HashUtil.deep_symbolize_keys(redis.hgetall("mime_application_count")),
        :pages_count => HashUtil.deep_symbolize_keys(redis.hgetall("pages_count")),
        :assets_count => HashUtil.deep_symbolize_keys(redis.hgetall("assets_count"))
    }
    ap @crawl
    haml :statistics
  end
  
  # Starts the Sinatra server, and kills the processes when shutdown
  def self.start
    unless Server.running?
      thread = Thread.new do
        puts "Starting Sinatra"
        Server.run!
        puts "Stopping crawl..."
        ## we need to manually kill the main thread as sinatra traps the interrupts
        Thread.main.kill
      end
    end    
  end  
  
end

# Monkey Patch of the Numeric class
class Numeric
  
  #Returns a human readable format for a number representing a data size
  def to_human
    units = %w{B KB MB GB TB}
    ap self
    e = 0
    e = (Math.log(self)/Math.log(1024)).floor unless self==0
    s = "%.3f" % (to_f / 1024**e)
    s.sub(/\.?0*$/, units[e])
  end
end