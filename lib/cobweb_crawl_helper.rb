# The crawl class gives easy access to information about the crawl, and gives the ability to stop a crawl
class CobwebCrawlHelper
  
  attr_accessor :id
  
  BATCH_SIZE = 200
  FINISHED = "Finished"
  STARTING = "Starting"
  CANCELLED = "Cancelled"
  
  def initialize(data)
    @data = data
    @stats = Stats.new(data)
  end
  
  def destroy
    queue_name = "cobweb_crawl_job"
    # set status as cancelled now so that we don't enqueue any further pages
    self.statistics.end_crawl(@data, true)
    
    job_items = Resque.peek(queue_name, 0, BATCH_SIZE)
    batch_count = 0
    until job_items.empty?
      
      job_items.each do |item|
        if item["args"][0]["crawl_id"] == id
          # remote this job from the queue
          Resque.dequeue(CrawlJob, item["args"][0])
        end
      end
      
      position = batch_count*BATCH_SIZE
      batch_count += 1
      job_items = Resque.peek(queue_name, position, BATCH_SIZE)
    end
    
  end
  
  def statistics
    @stats
  end
  
  def status
    statistics.get_status
  end
  
  def id
    @data[:crawl_id]
  end
  
end