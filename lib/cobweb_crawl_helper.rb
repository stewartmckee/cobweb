# The crawl class gives easy access to information about the crawl, and gives the ability to stop a crawl
class CobwebCrawlHelper
  
  attr_accessor :id
  
  BATCH_SIZE = 200
  FINISHED = "Finished"
  STARTING = "Starting"
  CANCELLED = "Cancelled"
  
  def initialize(data)
    @data = data
    
    # TAKING A LONG TIME TO RUN ON PRODUCTION BOX
    @stats = Stats.new(data)
  end
  
  def destroy(options)
    
    options[:queue_name] = "cobweb_crawl_job" unless options.has_key?(:queue_name)
    options[:finished_resque_queue] = CobwebFinishedJob unless options.has_key?(:finished_resque_queue)
    
    # set status as cancelled now so that we don't enqueue any further pages
    self.statistics.end_crawl(@data, true)
    puts "end_crawl: #{self.statistics.get_status}"
    if options[:finished_resque_queue]
      puts "enqueueing finished job..."
      
      additional_stats = {:crawl_id => id, :crawled_base_url => @stats.redis.get("crawled_base_url")}
      additional_stats[:redis_options] = @data[:redis_options] unless @data[:redis_options] == {}
      additional_stats[:source_id] = options[:source_id] unless options[:source_id].nil?
      
      Resque.enqueue(options[:finished_resque_queue], @stats.get_statistics.merge(additional_stats))
    end
    
    position = 0
    job_items = Resque.peek(options[:queue_name], position, BATCH_SIZE)
    until job_items.empty?
      puts "Batch: #{position} : #{job_items.count}"
      job_items.each do |item|
        if item["args"][0]["crawl_id"] == id
          # remove this job from the queue
          Resque.dequeue(CrawlJob, item["args"][0])
        end
      end
      
      job_items = Resque.peek(options[:queue_name], position+=BATCH_SIZE, BATCH_SIZE)
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