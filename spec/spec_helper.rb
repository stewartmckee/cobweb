require File.expand_path(File.dirname(__FILE__) + '/../lib/sidekiq/cobweb_helper')
require File.expand_path(File.dirname(__FILE__) + '/../lib/cobweb')
require File.expand_path(File.dirname(__FILE__) + '/../spec/samples/sample_server')
require File.expand_path(File.dirname(__FILE__) + '/../spec/http_stubs')
require 'mock_redis'
require 'thin' if ENV["TRAVIS_RUBY_VERSION"].nil?
require 'sidekiq'

require 'coveralls'
Coveralls.wear!

# Sets up the environment as test so that exceptions are raised
ENVIRONMENT = "test"
APP_ROOT = File.expand_path(File.dirname(__FILE__) + '/../')

RSpec.configure do |config|
  
  if ENV["TRAVIS_RUBY_VERSION"] || ENV['CI']
    config.filter_run_excluding :local_only => true
  end

  Thread.new do
    @thin ||= Thin::Server.start("0.0.0.0", 3532, SampleServer.app)
  end

  # WAIT FOR START TO COMPLETE
  sleep 1

  
  config.before(:all) {
    # START THIN SERVER TO HOST THE SAMPLE SITE FOR CRAWLING
  }
  
  config.before(:each) {
        
    #redis_mock = double("redis")
    #redis_mock.stub(:new).and_return(@redis_mock_object)
    
    #redis_mock.flushdb
    
  }

end
