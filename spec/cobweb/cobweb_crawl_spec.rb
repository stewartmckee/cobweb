require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

describe CobwebModule::Crawl, :local_only => true do

  before(:each) do
    @local_redis = {:host => "localhost", :port => 6379}
    @remote_redis = {:host => "remote-redis", :port => 6379}
    
    @request = {:crawl_id => "test_crawl_id"}
  end

  describe "remote redis" do
    before(:each) do
      @local = CobwebModule::Crawl.new(:redis_options => @local_redis)
      @remote = CobwebModule::Crawl.new(:redis_options => @remote_redis)

      @local.redis.del("test_redis")
      @remote.redis.del("test_redis")
      
    end
    it "should connect to the local redis" do
      @local.redis.exists("test_redis").should be_false
      @local.redis.set("test_redis", 1)
      @local.redis.exists("test_redis").should be_true

      @remote.redis.exists("test_redis").should be_false
    end
    it "should connect to the remote redis" do
      @remote.redis.exists("test_redis").should be_false
      @remote.redis.set("test_redis", 1)
      @remote.redis.exists("test_redis").should be_true
      
      @local.redis.exists("test_redis").should be_false
    end
  end
end
