require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

describe CobwebCrawler do

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

  end  

  describe "with mock" do

    
    it "should generate a cobweb_crawler object" do
      CobwebCrawler.new.should be_an_instance_of CobwebCrawler
    end
    
    describe "crawl" do
      it "should crawl a site" do
        crawler = CobwebCrawler.new({:cache => false, :quiet => false, :debug => false, :crawl_limit => 10})
        
        statistics = crawler.crawl("http://www.boeing.com/")
        
        ap statistics
        
      end
    end  
  end  

end 
