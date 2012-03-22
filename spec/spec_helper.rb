require File.expand_path(File.dirname(__FILE__) + '/../lib/cobweb')
require 'mock_redis'

RSpec.configure do |config|
  config.before(:each) {
    #redis_mock = double("redis")
    #ap redis_mock
    #redis_mock.stub(:new).and_return(MockRedis.new)
    
    Redis.new.flushdb
    
    
    @default_headers = {"Cache-Control" => "private, max-age=0",
                        "Date" => "Wed, 10 Nov 2010 09:06:17 GMT",
                        "Expires" => "-1",
                        "Content-Type" => "text/html; charset=UTF-8",
                        "Content-Encoding" => "",
                        "Transfer-Encoding" => "chunked",
                        "Server" => "gws",
                        "X-XSS-Protection" => "1; mode=block"}

    @mock_http_client = mock(Net::HTTP)
    @mock_http_request = mock(Net::HTTPRequest)
    @mock_http_redirect_request = mock(Net::HTTPRequest)
    @mock_http_redirect_request2 = mock(Net::HTTPRequest)
    
    @mock_http_response = mock(Net::HTTPResponse)
    @mock_http_redirect_response = mock(Net::HTTPRedirection)
    @mock_http_redirect_response2 = mock(Net::HTTPRedirection)
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
    @mock_http_client.stub!(:address).and_return("www.baseurl.com")
    @mock_http_client.stub!(:port).and_return("80 ")
    
    @mock_http_response.stub!(:code).and_return(200)
    @mock_http_response.stub!(:content_type).and_return("text/html")
    @mock_http_response.stub!(:[]).with("Content-Type").and_return(@default_headers["Content-Type"])
    @mock_http_response.stub!(:[]).with("location").and_return(@default_headers["location"])
    @mock_http_response.stub!(:[]).with("Content-Encoding").and_return(@default_headers["Content-Encoding"])
    @mock_http_response.stub!(:content_length).and_return(1024)
    @mock_http_response.stub!(:body).and_return("asdf")
    @mock_http_response.stub!(:to_hash).and_return(@default_headers)
    
    @mock_http_redirect_response.stub!(:code).and_return(301)
    @mock_http_redirect_response.stub!(:content_type).and_return("text/html")
    @mock_http_redirect_response.stub!(:[]).with("Content-Type").and_return(@default_headers["Content-Type"])
    @mock_http_redirect_response.stub!(:[]).with("location").and_return("http://redirected-to.com/redirect2.html")
    @mock_http_redirect_response.stub!(:[]).with("Content-Encoding").and_return(@default_headers["Content-Encoding"])
    @mock_http_redirect_response.stub!(:content_length).and_return(2048)
    @mock_http_redirect_response.stub!(:body).and_return("redirected body")
    @mock_http_redirect_response.stub!(:to_hash).and_return(@default_headers)
    
    @mock_http_redirect_response2.stub!(:code).and_return(301)
    @mock_http_redirect_response2.stub!(:content_type).and_return("text/html")
    @mock_http_redirect_response2.stub!(:[]).with("Content-Type").and_return(@default_headers["Content-Type"])
    @mock_http_redirect_response2.stub!(:[]).with("location").and_return("http://redirected-to.com/redirected.html")
    @mock_http_redirect_response2.stub!(:[]).with("Content-Encoding").and_return(@default_headers["Content-Encoding"])
    @mock_http_redirect_response2.stub!(:content_length).and_return(2048)
    @mock_http_redirect_response2.stub!(:body).and_return("redirected body")
    @mock_http_redirect_response2.stub!(:to_hash).and_return(@default_headers)
  }

end
