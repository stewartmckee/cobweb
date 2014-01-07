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
  s.add_dependency('redis')
  s.add_dependency('nokogiri')
  s.add_dependency('addressable')
  s.add_dependency('awesome_print')
  s.add_dependency('sinatra')
  s.add_dependency('haml')
  s.add_dependency('namespaced_redis')
  s.add_dependency('json')
  s.add_dependency('slop')
  
  s.add_development_dependency('rspec')
  s.add_development_dependency('thin')
end
