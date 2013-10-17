
require File.expand_path(File.dirname(__FILE__) + '/sidekiq/cobweb_helper')

# If your client is single-threaded, we just need a single connection in our Redis connection pool
#Sidekiq.configure_client do |config|
#  config.redis = { :namespace => 'x', :size => 1, :url => 'redis://localhost:6379/14' }
#end

# Sidekiq server is multi-threaded so our Redis connection pool size defaults to concurrency (-c)
#Sidekiq.configure_server do |config|
#  config.redis = { :namespace => 'x', :url => 'redis://localhost:6379/14' }
#end

class CrawlProcessWorker
  
  include Sidekiq::Worker

  sidekiq_options queue: "crawl_process_worker" if SIDEKIQ_INSTALLED
  
  def perform(content)
    content = HashUtil.deep_symbolize_keys(content)
    puts "Dummy Processing for #{content[:url]}"
  end
  def self.queue_size
    Sidekiq.redis do |conn|
      conn.llen("queue:#{get_sidekiq_options["queue"]}")
    end
  end
  
end