require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

describe Cobweb do

  before(:each) do
    @base_url = "http://www.baseurl.com/"
    @cobweb = Cobweb.new :quiet => true, :cache => nil
  end

  describe "detect finish of crawl" do
    
    describe "with no crawl limit" do
      before(:each) do
        @request = {
          :crawl_id => Digest::SHA1.hexdigest("#{Time.now.to_i}.#{Time.now.usec}"),
          :url => @base_url,
          :crawl_limit => nil
        }
      end
      
      it "should not limit crawl"
      it "should detect the end or crawl"
    end
    
    describe "with a crawl limit" do
      @request = {
        :crawl_id => Digest::SHA1.hexdigest("#{Time.now.to_i}.#{Time.now.usec}"),
        :url => @base_url,
        :crawl_limit => 3
      }

      it "should limit crawl"
      it "should detect the end or crawl based on limit"

    end
    
    
  end


end