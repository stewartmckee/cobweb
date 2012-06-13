require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

describe Cobweb, :local_only => true do

  before(:all) do
    #store all existing resque process ids
    @existing_processes = `ps aux | grep resque | grep -v grep | grep -v resque-web | awk '{print $2}'`.split("\n")
  
    # START WORKERS ONLY FOR CRAWL QUEUE SO WE CAN COUNT ENQUEUED PROCESS AND FINISH QUEUES
    puts "Starting Workers... Please Wait..."
    `mkdir log`
    io = IO.popen("nohup rake resque:workers PIDFILE=./tmp/pids/resque.pid COUNT=5 QUEUE=cobweb_crawl_job > log/output.log &")
    puts "Workers Started."
  
    # START THIN SERVER TO HOST THE SAMPLE SITE FOR CRAWLING
    @thin = nil
    Thread.new do
      @thin = Thin::Server.start("0.0.0.0", 3532, SampleServer.app)
    end
  
    # WAIT FOR START TO COMPLETE
    sleep 1
  
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
        :cache => nil
      }
      @cobweb = Cobweb.new @request
    end
  
    it "should crawl entire site" do
      crawl = @cobweb.start(@base_url)
      @stat = Stats.new({:crawl_id => crawl[:crawl_id]})
      wait_for_crawl_finished crawl[:crawl_id]
      Resque.size("cobweb_process_job").should == @base_page_count
    end
    it "detect crawl finished" do
      crawl = @cobweb.start(@base_url)
      @stat = Stats.new({:crawl_id => crawl[:crawl_id]})
      wait_for_crawl_finished crawl[:crawl_id]
      Resque.size("cobweb_finished_job").should == 1
    end
  end
  
  describe "with a crawl limit" do
    before(:each) do
      @request = {
        :crawl_id => Digest::SHA1.hexdigest("#{Time.now.to_i}.#{Time.now.usec}"),
        :quiet => true,
        :cache => nil
      }
      @cobweb = Cobweb.new @request
    end
  
    describe "limit to 1" do
      before(:each) do
        @request[:crawl_limit] = 1
      end

      it "should not crawl the entire site" do
        crawl = @cobweb.start(@base_url)
        @stat = Stats.new({:crawl_id => crawl[:crawl_id]})
        wait_for_crawl_finished crawl[:crawl_id]
        Resque.size("cobweb_process_job").should_not == @base_page_count
      end      
      it "should only crawl 1 page" do
        crawl = @cobweb.start(@base_url)
        @stat = Stats.new({:crawl_id => crawl[:crawl_id]})
        wait_for_crawl_finished crawl[:crawl_id]
        Resque.size("cobweb_process_job").should == 1
      end      
      it "should notify of crawl finished" do
        crawl = @cobweb.start(@base_url)
        @stat = Stats.new({:crawl_id => crawl[:crawl_id]})
        wait_for_crawl_finished crawl[:crawl_id]
        Resque.size("cobweb_finished_job").should == 1
      end      
    
    end
  
    describe "limit to 3" do
      before(:each) do
        @request[:crawl_limit] = 3
      end
      it "should not crawl the entire site" do
        crawl = @cobweb.start(@base_url)
        @stat = Stats.new({:crawl_id => crawl[:crawl_id]})
        wait_for_crawl_finished crawl[:crawl_id]
        Resque.size("cobweb_process_job").should_not == @base_page_count
      end      
      it "should notify of crawl finished" do
        crawl = @cobweb.start(@base_url)
        @stat = Stats.new({:crawl_id => crawl[:crawl_id]})
        wait_for_crawl_finished crawl[:crawl_id]
        Resque.size("cobweb_finished_job").should == 1
      end      
      it "should only crawl 3 pages" do
        crawl = @cobweb.start(@base_url)
        @stat = Stats.new({:crawl_id => crawl[:crawl_id]})
        wait_for_crawl_finished crawl[:crawl_id]
        Resque.size("cobweb_process_job").should == 3
      end      
    
    end
  
    describe "limit to 100" do
      before(:each) do
        @request[:crawl_limit] = 100
      end
    
      it "should crawl the entire site" do
        crawl = @cobweb.start(@base_url)
        @stat = Stats.new({:crawl_id => crawl[:crawl_id]})
        wait_for_crawl_finished crawl[:crawl_id]
        Resque.size("cobweb_process_job").should == @base_page_count
      end      
      it "should notify of crawl finished" do
        crawl = @cobweb.start(@base_url)
        @stat = Stats.new({:crawl_id => crawl[:crawl_id]})
        wait_for_crawl_finished crawl[:crawl_id]
        Resque.size("cobweb_finished_job").should == 1
      end      
      it "should not crawl 100 pages" do
        crawl = @cobweb.start(@base_url)
        @stat = Stats.new({:crawl_id => crawl[:crawl_id]})
        wait_for_crawl_finished crawl[:crawl_id]
        Resque.size("cobweb_process_job").should_not == 100
      end      
    end    
  end

  after(:all) do
    @all_processes = `ps aux | grep resque | grep -v grep | grep -v resque-web | awk '{print $2}'`.split("\n")
    command = "kill #{(@all_processes - @existing_processes).join(" ")}"
    IO.popen(command)
    #@thin.stop!    
  end

end

def wait_for_crawl_finished(crawl_id, timeout=20)
  counter = 0 
  while(running?(crawl_id) && counter < timeout) do
    sleep 1
    counter+=1
  end
  if counter > timeout
    raise "End of crawl not detected"
  end 
end

def running?(crawl_id)
  @stat.get_status != "Crawl Stopped"
end

def clear_queues
  Resque.queues.each do |queue|
    Resque.remove_queue(queue)
  end
  
  Resque.size("cobweb_process_job").should == 0
  Resque.size("cobweb_finished_job").should == 0      
end


