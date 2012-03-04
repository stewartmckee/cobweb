require 'cobweb'

crawler = CobwebCrawler.new(:cache => 600);

stats = crawler.crawl("http://www.pepsico.com")

ap stats
