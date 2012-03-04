require 'cobweb'

cobweb = CobwebCrawler.new(:cache => 600);

stats = crawler.crawl("http://www.rockwellcottage.com")

ap stats
