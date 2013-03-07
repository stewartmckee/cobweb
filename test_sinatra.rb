require 'cobweb'

crawler = CobwebCrawler.new(:cache => 600, :web_statistics => true);

stats = crawler.crawl("http://www.pepsico.com")

ap stats
