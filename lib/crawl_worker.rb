require 'sidekiq'
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
  sidekiq_options queue: "crawl_worker"
  sidekiq_options retry: false
  
  def perform(content)
    puts "performing crawl worker task"
    CrawlHelper.crawl_page(content)
  end
  def self.jobs
    Sidekiq.redis do |conn|
      conn.smembers(get_sidekiq_options[:queue]).count
    end
  end
  
end