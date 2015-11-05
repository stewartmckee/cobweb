require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

describe CobwebCrawlHelper do
  include HttpStubs
  before(:each) do
    pending("requires resque or sidekiq") unless RESQUE_INSTALLED || SIDEKIQ_INSTALLED

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

      describe "the destroy method " do
        before(:each) do
          if SIDEKIQ_INSTALLED
            if Sidekiq::Queue.new("crawl_worker").size > 0
              raise "cobweb_crawl_job is not empty, do not run specs until it is!"
            end
          elsif RESQUE_INSTALLED
            if Resque.size("cobweb_crawl_job") > 0
              raise "cobweb_crawl_job is not empty, do not run specs until it is!"
            end
          end

          105.times do |item_count|
            2.times do |crawl_count|
              if SIDEKIQ_INSTALLED
                item_data = {:crawl_id => "crawl_#{crawl_count}_id", :url => "http://crawl#{crawl_count}.com/page#{item_count}.html"}
                CrawlWorker.perform_async(item_data)
              elsif RESQUE_INSTALLED
                item_data = {:crawl_id => "crawl_#{crawl_count}_id", :url => "http://crawl#{crawl_count}.com/page#{item_count}.html"}
                Resque.enqueue(CrawlJob, item_data)
              end
            end
          end
        end
        after(:each) do
          Sidekiq::Queue.new("crawl_worker").clear if SIDEKIQ_INSTALLED
          Resque.remove_queue("cobweb_crawl_job") if RESQUE_INSTALLED
        end
        it "should have a queue length of 210" do
          Sidekiq::Queue.new("crawl_worker").size.should == 210 if SIDEKIQ_INSTALLED
          Resque.size("cobweb_crawl_job").should == 210 if RESQUE_INSTALLED
        end
        describe "after called" do
          before(:each) do
            if SIDEKIQ_INSTALLED
              @crawl = CobwebCrawlHelper.new({:crawl_id => "crawl_0_id", :queue_system => :sidekiq}) if SIDEKIQ_INSTALLED
            elsif RESQUE_INSTALLED
              @crawl = CobwebCrawlHelper.new({:crawl_id => "crawl_0_id", :queue_system => :resque}) if RESQUE_INSTALLED
            end
            @crawl.destroy
          end
          it "should delete only the crawl specified" do
            if SIDEKIQ_INSTALLED
              Sidekiq::Queue.new("crawl_worker").size.should == 105
            elsif RESQUE_INSTALLED
              Resque.size("cobweb_crawl_job").should == 105
            end

          end
          it "should not contain any crawl_0_id" do
            if SIDEKIQ_INSTALLED
              Sidekiq::Queue.new("crawl_job").each do |item|
                item.args[0]["crawl_id"].should_not == "crawl_0_id"
              end
            elsif RESQUE_INSTALLED
              Resque.peek("cobweb_crawl_job", 0, 200).map{|i| i["args"][0]}.each do |item|
                item["crawl_id"].should_not == "crawl_0_id"
              end
            end
          end
          it "should only contain crawl_1_id" do
            if SIDEKIQ_INSTALLED
              Sidekiq::Queue.new("crawl_job").each do |item|
                item.args[0]["crawl_id"].should == "crawl_1_id"
              end
            elsif RESQUE_INSTALLED
              Resque.peek("cobweb_crawl_job", 0, 200).map{|i| i["args"][0]}.each do |item|
                item["crawl_id"].should == "crawl_1_id"
              end
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
