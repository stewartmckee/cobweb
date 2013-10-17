
require File.expand_path(File.dirname(__FILE__) + '/sidekiq/cobweb_helper')

# If your client is single-threaded, we just need a single connection in our Redis connection pool
#Sidekiq.configure_client do |config|
#  config.redis = { :namespace => 'x', :size => 1, :url => 'redis://localhost:6379/14' }
#end

# Sidekiq server is multi-threaded so our Redis connection pool size defaults to concurrency (-c)
#Sidekiq.configure_server do |config|
#  config.redis = { :namespace => 'x', :url => 'redis://localhost:6379/14' }
#end

class CrawlFinishedWorker
  
  include Sidekiq::Worker

  sidekiq_options queue: "crawl_finished_worker" if SIDEKIQ_INSTALLED
  
  def perform(statistics)
    puts "Dummy Finished Job"

    ap statistics
    
  end
end