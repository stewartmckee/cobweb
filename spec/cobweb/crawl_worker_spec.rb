require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')
#require 'sidekiq/testing'

describe CrawlWorker, :local_only => true do

  before(:all) do
    #store all existing resque process ids so we don't kill them afterwards
    @existing_processes = `ps aux | grep sidekiq | grep -v grep | awk '{print $2}'`.split("\n")
    puts @existing_processes
    @existing_processes.should be_empty
  
    # START WORKERS ONLY FOR CRAWL QUEUE SO WE CAN COUNT ENQUEUED PROCESS AND FINISH QUEUES
    puts "Starting Workers... Please Wait..."
    `mkdir log`
    `rm -rf output.log`
    io = IO.popen("nohup sidekiq -r ./lib/crawl_worker.rb -q crawl_worker > ./log/output.log &")
    puts "Workers Started."
  
  end

  before(:each) do
    @base_url = "http://localhost:3532/"
    @base_page_count = 77
  
    clear_queues
  end

  describe "with no crawl limit" do
    before(:each) do
      @request = {
        :crawl_id => Digest::SHA1.hexdigest("#{Time.now.to_i}.#{Time.now.usec}"),
        :crawl_limit => nil,
        :quiet => false,
        :debug => false,
        :cache => nil,
        :queue_system => :sidekiq
      }
      @cobweb = Cobweb.new @request
    end
  
    it "should crawl entire site" do
      crawl = @cobweb.start(@base_url)
      @stat = Stats.new({:crawl_id => crawl[:crawl_id]})
      wait_for_crawl_finished crawl[:crawl_id]
      CrawlProcessWorker.queue_size.should == @base_page_count
    end
    it "detect crawl finished" do
      crawl = @cobweb.start(@base_url)
      @stat = Stats.new({:crawl_id => crawl[:crawl_id]})
      wait_for_crawl_finished crawl[:crawl_id]
      CrawlFinishedWorker.queue_size.should == 1
    end
  end
  describe "with limited mime_types" do
    before(:each) do
      @request = {
        :crawl_id => Digest::SHA1.hexdigest("#{Time.now.to_i}.#{Time.now.usec}"),
        :quiet => true,
        :cache => nil,
        :queue_system => :sidekiq,
        :valid_mime_types => ["text/html"]
      }
      @cobweb = Cobweb.new @request
    end
      
    it "should only crawl html pages" do
      crawl = @cobweb.start(@base_url)
      @stat = Stats.new({:crawl_id => crawl[:crawl_id]})
      wait_for_crawl_finished crawl[:crawl_id]
      CrawlProcessWorker.queue_size.should == 8

      mime_types = CrawlProcessWorker.queue_items(0, 100).map{|job| JSON.parse(job)["args"][0]["mime_type"]}

      mime_types.count.should == 8
      mime_types.map{|m| m.should == "text/html"}
      mime_types.select{|m| m=="text/html"}.count.should == 8
      
      
    end
    
  end
  describe "with a crawl limit" do
    before(:each) do
      @request = {
        :crawl_id => Digest::SHA1.hexdigest("#{Time.now.to_i}.#{Time.now.usec}"),
        :quiet => true,
        :queue_system => :sidekiq,
        :cache => nil
      }
    end
  
    describe "of 1" do
      before(:each) do
        @request[:crawl_limit] = 1
        @cobweb = Cobweb.new @request
      end
  
      it "should not crawl the entire site" do
        crawl = @cobweb.start(@base_url)
        @stat = Stats.new({:crawl_id => crawl[:crawl_id]})
        wait_for_crawl_finished crawl[:crawl_id]
        CrawlProcessWorker.queue_size.should_not == @base_page_count
      end      
      it "should only crawl 1 page" do
        crawl = @cobweb.start(@base_url)
        @stat = Stats.new({:crawl_id => crawl[:crawl_id]})
        wait_for_crawl_finished crawl[:crawl_id]
        CrawlProcessWorker.queue_size.should == 1
      end      
      it "should notify of crawl finished" do
        crawl = @cobweb.start(@base_url)
        @stat = Stats.new({:crawl_id => crawl[:crawl_id]})
        wait_for_crawl_finished crawl[:crawl_id]
        CrawlFinishedWorker.queue_size.should == 1
      end      
    
    end
  
    describe "of 5" do
      before(:each) do
        @request[:crawl_limit] = 5
      end

      describe "limiting count to html pages only" do
        before(:each) do
          @request[:crawl_limit_by_page] = true
          @cobweb = Cobweb.new @request
        end
      
        it "should only use html pages towards the crawl limit" do
          crawl = @cobweb.start(@base_url)
          @stat = Stats.new({:crawl_id => crawl[:crawl_id]})
          wait_for_crawl_finished crawl[:crawl_id]
        
          mime_types = CrawlProcessWorker.queue_items(0, 200).map{|job| JSON.parse(job)["args"][0]["mime_type"]}
          ap mime_types
          mime_types.select{|m| m=="text/html"}.count.should == 5
        end
      end
    end
  
    describe "of 10" do
      before(:each) do
        @request[:crawl_limit] = 10
        @cobweb = Cobweb.new @request
      end
      
      it "should not crawl the entire site" do
        crawl = @cobweb.start(@base_url)
        @stat = Stats.new({:crawl_id => crawl[:crawl_id]})
        wait_for_crawl_finished crawl[:crawl_id]
        CrawlProcessWorker.queue_size.should_not == @base_page_count
      end      
      it "should notify of crawl finished" do
        crawl = @cobweb.start(@base_url)
        @stat = Stats.new({:crawl_id => crawl[:crawl_id]})
        wait_for_crawl_finished crawl[:crawl_id]
        CrawlFinishedWorker.queue_size.should == 1
      end      
      it "should only crawl 10 objects" do
        crawl = @cobweb.start(@base_url)
        @stat = Stats.new({:crawl_id => crawl[:crawl_id]})
        wait_for_crawl_finished crawl[:crawl_id]
        CrawlProcessWorker.queue_size.should == 10
      end
    end
  
    describe "of 100" do
      before(:each) do
        @request[:crawl_limit] = 100
        @cobweb = Cobweb.new @request
      end
      
      it "should crawl the entire sample site" do
        crawl = @cobweb.start(@base_url)
        @stat = Stats.new({:crawl_id => crawl[:crawl_id]})
        wait_for_crawl_finished crawl[:crawl_id]
        CrawlProcessWorker.queue_size.should == @base_page_count
      end      
      it "should notify of crawl finished" do
        crawl = @cobweb.start(@base_url)
        @stat = Stats.new({:crawl_id => crawl[:crawl_id]})
        wait_for_crawl_finished crawl[:crawl_id]
        CrawlFinishedWorker.queue_size.should == 1
      end      
      it "should not crawl 100 pages" do
        crawl = @cobweb.start(@base_url)
        @stat = Stats.new({:crawl_id => crawl[:crawl_id]})
        wait_for_crawl_finished crawl[:crawl_id]
        CrawlProcessWorker.queue_size.should_not == 100
      end      
    end    
  end

  after(:all) do
    @all_processes = `ps aux | grep sidekiq | grep -v grep | grep -v sidekiq-web | awk '{print $2}'`.split("\n")
    unless (@all_processes - @existing_processes).empty?
      command = "kill #{(@all_processes - @existing_processes).join(" ")}"
      IO.popen(command)
    end
    clear_queues
  end

end

def wait_for_crawl_finished(crawl_id, timeout=20)
  @counter = 0
  start_time = Time.now
  while(running?(crawl_id) && Time.now < start_time + timeout) do
    sleep 1
  end
  if Time.now > start_time + timeout
    raise "End of crawl not detected"
  end
end

def running?(crawl_id)
  status = @stat.get_status
  result = true
  if status == CobwebCrawlHelper::STARTING
    result = true
  else
    if status == @last_stat
      if @counter > 20
        raise "Static status: #{status}"
      else
        @counter += 1
      end
    else
      result = status != CobwebCrawlHelper::FINISHED && status != CobwebCrawlHelper::CANCELLED
    end
  end
  @last_stat = @stat.get_status
  result
end

def clear_queues
  Sidekiq.redis do |conn|
    conn.smembers("queues").each do |queue_name|
      conn.del("queue:#{queue_name}")
      conn.srem("queues", queue_name)
    end
  end
  sleep 2
  
  CrawlProcessWorker.queue_size.should == 0
  CrawlFinishedWorker.queue_size.should == 0
end


