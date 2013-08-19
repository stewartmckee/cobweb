require 'sinatra'
require 'haml'

# Sinatra server to host the statistics for the CobwebCrawler
class Server < Sinatra::Base

  set :root, File.dirname(__FILE__)
  set :views, settings.root + '/../views'
  set :public_folder, settings.root + '/../public'
  set :bind, '0.0.0.0'
  enable :static
  
  # Sinatra Dashboard
  get '/' do
    @full_redis = Redis.new(redis_options)
    @colors = ["#00366f", "#006ba0", "#3F0BDB", "#396CB3"]
    
    @crawls = []
    @full_redis.smembers("cobweb_crawls").each do |crawl_id|
      version = cobweb_version(crawl_id)
      if version == Cobweb.version
        redis = Redis::Namespace.new("cobweb-#{version}-#{crawl_id}", :redis => Redis.new(redis_options))
        stats = HashUtil.deep_symbolize_keys({
          :cobweb_version => version,
          :crawl_details => redis.hgetall("crawl_details"),
          :statistics => redis.hgetall("statistics"),
          :minute_totals => redis.hgetall("minute_totals"),
          })
        @crawls << stats
        @crawls.sort!{|a,b| b[:statistics][:crawl_started_at] <=> a[:statistics][:crawl_started_at]}
      end
    end
    
    haml :home
  end
  
  # Sinatra Crawl Detail
  get '/statistics/:crawl_id' do
    
    version = cobweb_version(params[:crawl_id])
    redis = Redis::Namespace.new("cobweb-#{version}-#{params[:crawl_id]}", :redis => Redis.new(redis_options))
    
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
        :cobweb_version => version,
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

    @dates = (1..30).to_a.reverse.map{|minutes| [(DateTime.now - (minutes/1440.0)).strftime("%Y-%m-%d %H:%M").to_sym, minutes] }
    haml :statistics
  end
  
  def cobweb_version(crawl_id)
    redis = Redis.new(redis_options)
    key = redis.keys("cobweb-*-#{crawl_id}:queued").first
    
    key =~ /cobweb-(.*?)-(.*?):queued/
    cobweb_version = $1
  end
  
  def redis_options
    Server.cobweb_options[:redis_options]
  end
  
  # Starts the Sinatra server, and kills the processes when shutdown
  def self.start(options={})
    @options = options
    @options[:redis_options] = {} unless @options.has_key? :redis_options
    unless Server.running?
      if @options[:run_as_server]
        puts "Starting Sinatra for cobweb v#{Cobweb.version}"
        Server.run!
        puts "Stopping crawl..."
      else
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
  
  def self.cobweb_options
    @options
  end
  
end

# Monkey Patch of the Numeric class
class Numeric
  
  #Returns a human readable format for a number representing a data size
  def to_human
    units = %w{B KB MB GB TB}
    e = 0
    e = (Math.log(self)/Math.log(1024)).floor unless self==0
    s = "%.3f" % (to_f / 1024**e)
    s.sub(/\.?0*$/, units[e])
  end
end