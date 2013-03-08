require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')
require File.expand_path(File.dirname(__FILE__) + '/../../lib/cobweb_links')

describe CobwebLinks do
  include HttpStubs
  before(:each) do
    setup_stubs
  
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

  
  it "should generate a cobweb_links object" do
    CobwebLinks.new(:internal_urls => [""]).should be_an_instance_of CobwebLinks
  end

  it "should raise error with no internal links" do
    expect {CobwebLinks.new()}.to raise_error(InternalUrlsMissingError)
  end    
  it "should not raise error with missing external links" do
    expect {CobwebLinks.new(:internal_urls => ["http://domain_one.com/"])}.to_not raise_error(InternalUrlsMissingError)
  end
  it "should raise error with invalid internal links" do
    expect {CobwebLinks.new(:internal_urls => "")}.to raise_error(InvalidUrlsError)
  end
  it "should raise error with invalid external links" do
    expect {CobwebLinks.new(:internal_urls => [], :external_urls => "")}.to raise_error(InvalidUrlsError)
  end
    
  
  describe "internal and external links" do
    it "should only return internal links" do
      cobweb_links = CobwebLinks.new(:internal_urls => ["http://domain_one.com/"], :external_urls => ["http://domain_two.com/"])
      cobweb_links.internal?("http://domain_one.com/pageone.html").should be_true
      cobweb_links.internal?("http://domain_one.com/pagetwo.html").should be_true
    end
    it "should not return external links" do
      cobweb_links = CobwebLinks.new(:internal_urls => ["http://domain_one.com/"], :external_urls => ["http://domain_two.com/"])
      cobweb_links.external?("http://domain_one.com/pageone.html").should be_false
      cobweb_links.external?("http://domain_two.com/pageone.html").should be_true      
      cobweb_links.external?("http://external.com/pageone.html").should be_true      
    end
    it "should override internal links with external links" do
      cobweb_links = CobwebLinks.new(:internal_urls => ["http://domain_one.com/"], :external_urls => ["http://domain_one.com/blog"])
      cobweb_links.internal?("http://domain_one.com/pageone.html").should be_true
      cobweb_links.external?("http://domain_one.com/pageone.html").should be_false
      cobweb_links.internal?("http://domain_one.com/blog/pageone.html").should be_false
      cobweb_links.external?("http://domain_one.com/blog/pageone.html").should be_true
      cobweb_links.internal?("http://domain_two.com/blog/pageone.html").should be_false
      cobweb_links.external?("http://domain_two.com/blog/pageone.html").should be_true
    end
  end
  it "should only match from beginning of url" do
    cobweb_links = CobwebLinks.new(:internal_urls => ["http://www.domain_one.com/"], :external_urls => ["http://www.domain_two.com/"])
    cobweb_links.internal?("http://www.domain_one.com/pageone.html").should be_true
    cobweb_links.internal?("http://www.domain_two.com/pageone.html").should be_false
    cobweb_links.internal?("http://www.domain_one.com/pageone.html?url=http://www.domain_two.com/pageone.html").should be_true
    cobweb_links.internal?("http://www.domain_two.com/pageone.html?url=http://www.domain_one.com/pageone.html").should be_false
  end
  
  describe "using wildcards" do
    it "should match internal links with wildcards" do
      cobweb_links = CobwebLinks.new(:internal_urls => ["http://*.domain_one.com/"], :external_urls => ["http://blog.domain_one.com/"])
      cobweb_links.internal?("http://www.domain_one.com/pageone.html").should be_true
      cobweb_links.internal?("http://images.domain_one.com/logo.png").should be_true      
      cobweb_links.internal?("http://blog.domain_one.com/pageone.html").should be_false
    end
    it "should match external links with wildcards" do
      cobweb_links = CobwebLinks.new(:internal_urls => ["http://www.domain_one.com/"], :external_urls => ["http://*.domain_one.com/"])
      cobweb_links.external?("http://www.domain_one.com/pageone.html").should be_true
      cobweb_links.external?("http://images.domain_one.com/logo.png").should be_true
      cobweb_links.external?("http://blog.domain_one.com/pageone.html").should be_true
    end
    it "should match external links with querystring parameters" do
      cobweb_links = CobwebLinks.new(:internal_urls => ["http://www.ford.com/"], :external_urls => ["http://*.ford.com/*?*view=print"])
      cobweb_links.external?("http://corporate.ford.com/news-center/press-releases-detail/pr-doug-scott2658-marketing-manager-31039?view=print").should be_true
      cobweb_links.internal?("http://corporate.ford.com/news-center/press-releases-detail/pr-doug-scott2658-marketing-manager-31039?view=print").should be_false
      cobweb_links.external?("http://corporate.ford.com/news-center/view=print/pr-doug-scott2658-marketing-manager-31039").should be_true
    end
    it "should allow multiple wildcards" do
      cobweb_links = CobwebLinks.new(:internal_urls => ["http://*.*.domain_one.com/"])
      cobweb_links.internal?("http://www.domain_one.com/pageone.html").should be_false
      cobweb_links.internal?("http://blog.domain_one.com/pageone.html").should be_false
      cobweb_links.internal?("http://www.marketing.domain_one.com/pageone.html").should be_true
      cobweb_links.internal?("http://blog.designers.domain_one.com/pagetwo.html").should be_true      
    end
    it "should allow multiple country tlds with wildcards" do
      cobweb_links = CobwebLinks.new(:internal_urls => ["http://*.domain_one.*/", "http://*.domain_one.*.*/"])
      cobweb_links.internal?("http://www.domain_one.com/pageone.html").should be_true
      cobweb_links.internal?("http://blog.domain_one.com/pageone.html").should be_true
      cobweb_links.internal?("http://www.domain_one.co.uk/pageone.html").should be_true
      cobweb_links.internal?("http://blog.domain_one.co.uk/pageone.html").should be_true
      cobweb_links.internal?("http://www.domain_one.com.au/pageone.html").should be_true
      cobweb_links.internal?("http://blog.domain_one.com.au/pageone.html").should be_true
      cobweb_links.internal?("http://www.domain_one.ie/pageone.html").should be_true
      cobweb_links.internal?("http://blog.domain_one.ie/pageone.html").should be_true
    end
  end
  
end