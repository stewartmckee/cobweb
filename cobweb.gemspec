# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require 'cobweb_version'

Gem::Specification.new do |s|

  s.name              = "cobweb"
  s.version           = CobwebVersion.version
  s.author            = "Stewart McKee"
  s.email             = "stewart@rockwellcottage.com"
  s.homepage          = "http://github.com/stewartmckee/cobweb"
  s.platform          = Gem::Platform::RUBY
  s.description       = "Cobweb is a web crawler that can use resque to cluster crawls to quickly crawl extremely large sites which is much more performant than multi-threaded crawlers.  It is also a standalone crawler that has a sophisticated statistics monitoring interface to monitor the progress of the crawls."
  s.summary           = "Cobweb is a web crawler that can use resque to cluster crawls to quickly crawl extremely large sites faster than multi-threaded crawlers.  It is also a standalone crawler that has a sophisticated statistics monitoring interface to monitor the progress of the crawls."
  s.files             = Dir["{spec,lib,views,public}/**/*"].delete_if { |f| f =~ /(rdoc)$/i }
  s.require_path      = "lib"
  s.has_rdoc          = false
  s.license           = 'MIT'
  s.extra_rdoc_files  = ["README.textile"]

  s.executables       = ["cobweb"]

  s.add_dependency('rake')
  s.add_dependency('redis', '>=3.2.1')
  s.add_dependency('nokogiri', '>=1.6.0')
  s.add_dependency('addressable', '>=2.3.8')
  s.add_dependency('sinatra', '>=1.4.6')
  s.add_dependency('haml', '>=4.0.7')
  s.add_dependency('redis-namespace', '>=1.5.2')
  s.add_dependency('json', '>=1.8.3')
  s.add_dependency('slop', ">=4.2.0")

  s.add_development_dependency("rspec")
  s.add_development_dependency("rspec-core")
  s.add_development_dependency("mock_redis")
  s.add_development_dependency("thin")
  s.add_development_dependency("coveralls")
  s.add_development_dependency("sidekiq")
  s.add_development_dependency("bundle-audit")
end
