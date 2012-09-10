class Crawl
  
  # this class describes the crawl
  
  attr_accessor :id, :status
  
  BATCH_SIZE=200
  
  
  def destroy(crawl_id)
    queue_name = "crawl_job"
    
    # lock redis so that we can't add more jobs
    Resque.redis.multi do
      item_count = Resque.size(queue)
      batches = item_count / BATCH_SIZE
      batches.times do |i|
        position = i*BATCH_SIZE
        job_items = Resque.peek(queue, position, position+BATCH_SIZE)
        
        job_items.each do |item|
          if item[:crawl_id] == crawl_id
            # remote this job from the queue
            Resque.dequeue(CrawlJob, item)
          end
        end
      end
    end
    
  end
  
end