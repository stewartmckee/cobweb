require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

describe CobwebCrawlHelper do
  include HttpStubs
  before(:each) do
    setup_stubs
  end
  # this spec tests the crawl object
  
  describe "initialize" do
    describe "without data" do
      it "should raise an exception" do
        lambda {CobwebCrawlHelper.new}.should raise_exception
      end
    end
    
    describe "with data" do
      before(:each) do
        data = {:crawl_id => "asdf"}
        @crawl = CobwebCrawlHelper.new(data)
      end
      it "should create a crawl object" do
        @crawl.should be_an_instance_of CobwebCrawlHelper
      end
      it "should return an id" do
        @crawl.should respond_to "id"
      end
      it "should return a status" do
        @crawl.should respond_to "status"
      end
      
      describe "the destroy method" do
        before(:each) do
          if Resque.size("cobweb_crawl_job") > 0
            raise "cobweb_crawl_job is not empty, do not run specs until it is!"
          end
          105.times do |item_count|
            2.times do |crawl_count|
              item_data = {:crawl_id => "crawl_#{crawl_count}_id", :url => "http://crawl#{crawl_count}.com/page#{item_count}.html"}
              Resque.enqueue(CrawlJob, item_data)
            end
          end
        end
        after(:each) do
          Resque.remove_queue("cobweb_crawl_job")
        end
        it "should have a queue length of 210" do
          Resque.size("cobweb_crawl_job").should == 210
        end
        describe "after called" do
          before(:each) do
            @crawl = CobwebCrawlHelper.new({:crawl_id => "crawl_0_id"})
            @crawl.destroy
          end
          it "should delete only the crawl specified" do
            Resque.size("cobweb_crawl_job").should == 105
          end
          it "should not contain any crawl_0_id" do
            Resque.peek("cobweb_crawl_job", 0, 200).map{|i| i["args"][0]}.each do |item|
              item["crawl_id"].should_not == "crawl_0_id"
            end
          end
          it "should only contain crawl_1_id" do
            Resque.peek("cobweb_crawl_job", 0, 200).map{|i| i["args"][0]}.each do |item|
              item["crawl_id"].should == "crawl_1_id"
            end
          end
          it "should set status to 'Cancelled'" do
            @crawl.status.should == "Cancelled"
          end
        end
      end
    end
  end
  
  
end