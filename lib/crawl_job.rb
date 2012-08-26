
# CrawlJob defines a resque job to perform the crawl
class CrawlJob
  
  @queue = :cobweb_crawl_job

  # Resque perform method to maintain the crawl, enqueue found links and detect the end of crawl
  def self.perform(content)
    
    CrawlHelper.crawl_page(content)
    
  end

end
