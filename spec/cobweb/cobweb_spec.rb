require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')
require "ap"

describe CobWeb do

  before(:each) do
  
    @base_url = "http://www.baseurl.com/"
  
    @default_headers = {"Cache-Control" => "private, max-age=0",
                        "Date" => "Wed, 10 Nov 2010 09:06:17 GMT",
                        "Expires" => "-1",
                        "Content-Type" => "text/html; charset=UTF-8",
                        "Content-Encoding" => "gzip",
                        "Transfer-Encoding" => "chunked",
                        "Server" => "gws",
                        "X-XSS-Protection" => "1; mode=block"}

    @cobweb = CobWeb.new :quiet => true, :cache => nil
  end  

  describe "with mock" do
    before(:each) do
      @mock_http_client = mock(Net::HTTP)
      @mock_http_request = mock(Net::HTTPRequest)
      @mock_http_redirect_request = mock(Net::HTTPRequest)
      @mock_http_redirect_request2 = mock(Net::HTTPRequest)
      
      @mock_http_response = mock(Net::HTTPResponse)
      @mock_http_redirect_response = mock(Net::HTTPRedirection)
      @mock_http_get = mock(Net::HTTP::Get)
      
      Net::HTTP.stub!(:new).and_return(@mock_http_client)
      Net::HTTP::Get.stub!(:new).and_return(@mock_http_request)
      Net::HTTP::Get.stub!(:new).with("/redirect.html").and_return(@mock_http_redirect_request)
      Net::HTTP::Get.stub!(:new).with("/redirect2.html").and_return(@mock_http_redirect_request2)
      
      @mock_http_client.stub!(:request).with(@mock_http_request).and_return(@mock_http_response)
      @mock_http_client.stub!(:request).with(@mock_http_redirect_request).and_return(@mock_http_redirect_response)      
      @mock_http_client.stub!(:request).with(@mock_http_redirect_request2).and_return(@mock_http_redirect_response2)
      @mock_http_client.stub!(:read_timeout=).and_return(nil)      
      @mock_http_client.stub!(:open_timeout=).and_return(nil)      
      @mock_http_client.stub!(:start).and_return(@mock_http_response)      
      
      @mock_http_response.stub!(:code).and_return(200)
      @mock_http_response.stub!(:content_type).and_return("text/html")
      @mock_http_response.stub!(:[]).with("Content-Type").and_return(@default_headers["Content-Type"])
      @mock_http_response.stub!(:[]).with("location").and_return(@default_headers["location"])
      @mock_http_response.stub!(:content_length).and_return(1024)
      @mock_http_response.stub!(:body).and_return("asdf")
      @mock_http_response.stub!(:to_hash).and_return(@default_headers)
      
      @mock_http_redirect_response.stub!(:code).and_return(301)
      @mock_http_redirect_response.stub!(:content_type).and_return("text/html")
      @mock_http_redirect_response.stub!(:[]).with("Content-Type").and_return(@default_headers["Content-Type"])
      @mock_http_redirect_response.stub!(:[]).with("location").and_return("http://redirected-to.com/redirect2.html")
      @mock_http_redirect_response.stub!(:content_length).and_return(2048)
      @mock_http_redirect_response.stub!(:body).and_return("redirected body")
      @mock_http_redirect_response.stub!(:to_hash).and_return(@default_headers)
      
      @mock_http_redirect_response2.stub!(:code).and_return(301)
      @mock_http_redirect_response2.stub!(:content_type).and_return("text/html")
      @mock_http_redirect_response2.stub!(:[]).with("Content-Type").and_return(@default_headers["Content-Type"])
      @mock_http_redirect_response2.stub!(:[]).with("location").and_return("http://redirected-to.com/redirected.html")
      @mock_http_redirect_response2.stub!(:content_length).and_return(2048)
      @mock_http_redirect_response2.stub!(:body).and_return("redirected body")
      @mock_http_redirect_response2.stub!(:to_hash).and_return(@default_headers)
      
    end
    
    it "should generate a cobweb object" do
      CobWeb.new.should be_an_instance_of CobWeb
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
          @cobweb = CobWeb.new(:follow_redirects => true, :quiet => true, :cache => nil)
        end
        
        it "should flow through redirect" #do
          
          #@mock_http_client.should_receive(:request).with(@mock_http_redirect_request).and_return(@mock_http_redirect_response)
          #@mock_http_client.should_receive(:request).with(@mock_http_redirect_request).and_return(@mock_http_redirect_response)
          #
          #content = @cobweb.get(@base_url)
          #content.should be_an_instance_of Hash
          #ap content
          #content[:url].should == "http://redirect-me.com/redirect.html"
          #content[:redirect_through].length.should == 2
          #content[:mime_type].should == "text/html"
          #content[:body].should == "asdf"
          
        #end
        it "should return the path followed" #do
          #@mock_http_client.should_receive(:request).with(@mock_http_redirect_request).and_return(@mock_http_redirect_response)
          #
          #content = @cobweb.get(@base_url)
          #content[:redirect_through].should == ["http://redirected-to.com/redirect2.html", "http://redirected-to.com/redirected.html"]
          
        #end
        it "should not follow with redirect disabled" do
          @cobweb = CobWeb.new(:follow_redirects => false, :cache => nil)
          @mock_http_client.should_receive(:start).and_return(@mock_http_redirect_response)
          
          content = @cobweb.get(@base_url)
          content[:url].should == "http://redirect-me.com/redirect.html"
          content[:redirect_through].should be_nil
          content[:status_code].should == 301
          content[:mime_type].should == "text/html"
          content[:body].should == "redirected body"

        end
      end
    end  
  end  

  describe "without mock" do
    it "should throw invalid url exception for an invalid url" do
      lambda {@cobweb.get("asdgas asv\"£%\"^%&*%")}.should raise_error URI::InvalidURIError
    end
    
    it "should throw exception when server is unavailable" #do
    #  lambda {@cobweb.get({:url => "http://www.oasdjgoisadjgoisdiog.com"})}.should raise_error URI::InvalidURIError
    #end
    
    it "should return a valid content hash when url doesn't exist on a live server" do
      status_code = @cobweb.get("http://test.com/laskdjflsdajf")[:status_code]
      status_code.should == 404
    end
    
  end
end 
