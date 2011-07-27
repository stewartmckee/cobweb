class CrawlFinishedJob
  require "ap"
  
  @queue = :crawl_finished_job

  def self.perform(statistics)
    content.symbolize_keys 
    puts "Dummy Finished Job"

    ap statistics
    
  end
end
