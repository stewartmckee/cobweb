require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')
require File.expand_path(File.dirname(__FILE__) + '/../../lib/content_link_parser.rb')

describe ContentLinkParser do

  before(:each) do
    @base_url = "http://www.baseurl.com/"
    @content = File.read(File.dirname(__FILE__) + "/../samples/sample_html_links.html")
    @content_parser = ContentLinkParser.new("http://sample-links.com/", @content)  
  end
  
  it "should load the sample document" do
    @content.should_not be_nil
    @content.should_not be_empty
  end
  
  it "should create a content link parser" do
    @content_parser.should_not be_nil
    @content_parser.should be_an_instance_of ContentLinkParser
  end
  
  describe "using default tags" do
    describe "returning general links" do
      it "should return some links from the sample data" do
        links = @content_parser.links 
        links.should_not be_nil
        links.should_not be_empty
      end
      it "should return the correct links" do
        links = @content_parser.links
        links.length.should == 4
      end
    end
    describe "returning image links" do
      it "should return some image links from the sample data" do
        links = @content_parser.images 
        links.should_not be_nil
        links.should_not be_empty
      end
      it "should return the correct links" do
        links = @content_parser.images
        links.length.should == 1
      end
    end
    describe "returning related links" do
      it "should return some related links from the sample data" do
        links = @content_parser.related 
        links.should_not be_nil
        links.should_not be_empty
      end
      it "should return the correct links" do
        links = @content_parser.related
        links.length.should == 2
      end
    end
    describe "returning script links" do
      it "should return some script links from the sample data" do
        links = @content_parser.scripts 
        links.should_not be_nil
        links.should_not be_empty
      end
      it "should return the correct links" do
        links = @content_parser.scripts
        links.length.should == 1
      end
    end
    describe "returning style links" do
      it "should return some style links from the sample data" do
        links = @content_parser.styles 
        links.should_not be_nil
        links.should_not be_empty
      end
      it "should return the correct links" do
        links = @content_parser.styles
        links.length.should == 3
      end
    end
    describe "returning unknown link type" do
      it "should return an empty array" do
        links = @content_parser.asdfasdfsadf
        links.should_not be_nil
        links.should be_an_instance_of Array
      end
    end
  end

  describe "returning all link data" do
    it "should return a hash with all link data" do
      link_data = @content_parser.link_data
      link_data.should_not be_nil
      link_data.should be_an_instance_of Hash
      
      link_data.keys.length.should == 5
      link_data[:links].length.should == 4
    end
  end
  
  describe "ignoring default tags" do
    it "should not return any links" do
      parser = ContentLinkParser.new("http://sample-links.com", @content, :ignore_default_tags => true)
      parser.links.should be_empty
    end
  end
end 
