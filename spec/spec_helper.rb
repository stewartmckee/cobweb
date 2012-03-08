require File.expand_path(File.dirname(__FILE__) + '/../lib/cobweb')
require 'mock_redis'

RSpec.configure do |config|
  config.before(:each) {
    #redis_mock = double("redis")
    #ap redis_mock
    #redis_mock.stub(:new).and_return(MockRedis.new)
    
  }

end
