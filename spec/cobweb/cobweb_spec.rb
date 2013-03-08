require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

describe Cobweb do

  include HttpStubs
  before(:each) do
    setup_stubs

    @base_url = "http://www.baseurl.com/"
    @cobweb = Cobweb.new :quiet => true, :cache => nil

    @default_options = {"User-Agent"=>"cobweb/#{CobwebVersion.version} (ruby/#{RUBY_VERSION} nokogiri/#{Nokogiri::VERSION})"}
  end
  
  it "should generate a cobweb object" do
    Cobweb.new.should be_an_instance_of Cobweb
  end
  
  it "should setup with defaults" do
    cobweb = Cobweb.new
    
    options = cobweb.instance_eval("@options")
    
    options[:follow_redirects].should == true
    options[:redirect_limit].should == 10
    options[:processing_queue].should == "CobwebProcessJob"
    options[:crawl_finished_queue].should == "CobwebFinishedJob"
    options[:quiet].should == true
    options[:debug].should == false
    options[:cache].should == 300
    options[:timeout].should == 10
    options[:redis_options].should == {}
    options[:internal_urls].should == []
    
  end
  
  describe "get" do
    it "should return a hash with default values" do
      @cobweb.get(@base_url).should be_an_instance_of Hash
    end
    
    it "should return a hash with default values without quiet option" do
      @cobweb.get(@base_url).should be_an_instance_of Hash
    end
    
    it "should raise exception if there is no url" do
      lambda {@cobweb.get(nil)}.should raise_error("url cannot be nil")
    end
    
    describe "content object" do
      it "should return the url" do
        @cobweb.get(@base_url)[:url].should == @base_url
      end
      it "should return correct content-type" do
        @mock_http_response.stub!(:content_type).and_return("image/jpeg")
        @cobweb.get(@base_url)[:mime_type].should == "image/jpeg"
      end
      it "should return correct status-code" do
        @mock_http_response.stub!(:code).and_return(404)
        @cobweb.get(@base_url)[:status_code].should == 404
      end
      it "should return correct status-code" do
        @mock_http_response.stub!(:code).and_return(404)
        @cobweb.get(@base_url)[:status_code].should == 404
      end
      it "should return correct character_set" do
        @cobweb.get(@base_url)[:character_set].should == "UTF-8"
      end 
      it "should return correct content_length" do
        @cobweb.get(@base_url)[:length].should == 1024
      end
      it "should return correct content_body" do
        @cobweb.get(@base_url)[:body].should == "asdf"
      end
      it "should return correct location" do
        @cobweb.get(@base_url)[:location].should == nil

        @mock_http_response.stub!(:[]).with("location").and_return("http://google.com/")
        @cobweb.get(@base_url)[:location].should == "http://google.com/"
      end
      it "should return correct headers" do
        @cobweb.get(@base_url)[:headers].should == @default_headers
      end
      it "should return correct a hash of links" do
        @cobweb.get(@base_url)[:links].should be_an_instance_of Hash
      end 
      it "should return the response time for the url" do
        @cobweb.get(@base_url)[:response_time].should be_an_instance_of Float 
      end
    end
    describe "with redirect" do
      
      before(:each) do
        @base_url = "http://redirect-me.com/redirect.html"
        @cobweb = Cobweb.new(:follow_redirects => true, :quiet => true, :cache => nil)
      end
      
      it "should return final page from redirects" do
        content = @cobweb.get(@base_url)
        content.should be_an_instance_of Hash
        content[:url].should == "http://redirected-to.com/redirected.html"
        content[:mime_type].should == "text/html"
        content[:body].should == "asdf"
      end
      it "should return the path followed" do
        
        content = @cobweb.get(@base_url)
        content[:redirect_through].should == ["http://redirect-me.com/redirect.html", "http://redirected-to.com/redirect2.html", "http://redirected-to.com/redirected.html"]
        
      end
      it "should not follow with redirect disabled" do
        @cobweb = Cobweb.new(:follow_redirects => false, :cache => 3)
        @mock_http_client.should_receive(:request).with(@mock_http_redirect_request).and_return(@mock_http_redirect_response)
        
        content = @cobweb.get(@base_url)
        content[:url].should == "http://redirect-me.com/redirect.html"
        content[:redirect_through].should be_nil
        content[:status_code].should == 301
        content[:mime_type].should == "text/html"
        content[:body].should == "redirected body"

      end
    end
    
    describe "with cache" do
      
      before(:each) do
        @cobweb = Cobweb.new :quiet => true, :cache => 1
        Redis.new.flushdb
      end
      
      describe "content object" do
        it "should return the url" do
          @cobweb.get(@base_url)[:url].should == @base_url
          @cobweb.get(@base_url)[:url].should == @base_url
        end
        it "should return correct content-type" do
          @mock_http_response.stub!(:content_type).and_return("image/jpeg")
          @cobweb.get(@base_url)[:mime_type].should == "image/jpeg"
          @cobweb.get(@base_url)[:mime_type].should == "image/jpeg"
        end
        it "should return correct status-code" do
          @mock_http_response.stub!(:code).and_return(404)
          @cobweb.get(@base_url)[:status_code].should == 404
          @cobweb.get(@base_url)[:status_code].should == 404
        end
        it "should return correct status-code" do
          @mock_http_response.stub!(:code).and_return(404)
          @cobweb.get(@base_url)[:status_code].should == 404
          @cobweb.get(@base_url)[:status_code].should == 404
        end
        it "should return correct character_set" do
          @cobweb.get(@base_url)[:character_set].should == "UTF-8"
          @cobweb.get(@base_url)[:character_set].should == "UTF-8"
        end 
        it "should return correct content_length" do
          @cobweb.get(@base_url)[:length].should == 1024
          @cobweb.get(@base_url)[:length].should == 1024
        end
        it "should return correct content_body" do
          @cobweb.get(@base_url)[:body].should == "asdf"
          @cobweb.get(@base_url)[:body].should == "asdf"
        end
        it "should return correct headers" do
          @cobweb.get(@base_url)[:headers].should == @symbolized_default_headers
          @cobweb.get(@base_url)[:headers].should == @symbolized_default_headers
        end
        it "should return correct a hash of links" do
          @cobweb.get(@base_url)[:links].should be_an_instance_of Hash
          @cobweb.get(@base_url)[:links].should be_an_instance_of Hash
        end 
        it "should return the response time for the url" do
          @cobweb.get(@base_url)[:response_time].should be_an_instance_of Float 
          @cobweb.get(@base_url)[:response_time].should be_an_instance_of Float 
        end
      end
    end
    describe "location setting" do
      it "Get should strip fragments" do
        Net::HTTP.should_receive(:new).with("www.google.com", 80)
        Net::HTTP::Get.should_receive(:new).with("/", @default_options)
        @cobweb.get("http://www.google.com/#ignore")
      end
      it "head should strip fragments" do
        Net::HTTP.should_receive(:new).with("www.google.com", 80)
        Net::HTTP::Head.should_receive(:new).with("/", {}).and_return(@mock_http_request)
        @cobweb.head("http://www.google.com/#ignore")
      end
      it "get should not strip path" do
        Net::HTTP.should_receive(:new).with("www.google.com", 80)
        Net::HTTP::Get.should_receive(:new).with("/path/to/stuff", @default_options)
        @cobweb.get("http://www.google.com/path/to/stuff#ignore")
      end
      it "get should not strip query string" do
        Net::HTTP.should_receive(:new).with("www.google.com", 80)
        Net::HTTP::Get.should_receive(:new).with("/path/to/stuff?query_string", @default_options)
        @cobweb.get("http://www.google.com/path/to/stuff?query_string#ignore")
      end
    end

  end  
end 
