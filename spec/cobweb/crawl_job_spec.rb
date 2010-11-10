require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')


describe CrawlJob do

  before(:each) do
    @base_url = "http://www.baseurl.com/"

    

    client = Net::HTTPClient.new
    puts client.get('http://www.google.com.au')
    puts "asdf"
    
    @cobweb = CobWeb.new("http://www.google.com")
    
  end
  
  it "should be a cobweb type" do
    @cobweb.should be_an_instance_of CobWeb
  end
  

end 
