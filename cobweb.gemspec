spec = Gem::Specification.new do |s|
  s.name              = "cobweb"
  s.version           = "0.0.19"
  s.author            = "Stewart McKee"
  s.email             = "stewart@rockwellcottage.com"
  s.homepage          = "http://github.com/stewartmckee/cobweb"
  s.platform          = Gem::Platform::RUBY
  s.summary           = "Web Crawler that uses resque background job engine to allow you to cluster your crawl."
  s.files             = Dir["{spec,lib,views}/**/*"].delete_if { |f| f =~ /(rdoc)$/i }
  s.require_path      = "lib"
  s.has_rdoc          = false
  s.extra_rdoc_files  = ["README.textile"]
  s.add_dependency('resque')
  s.add_dependency('redis')
  s.add_dependency('absolutize')
  s.add_dependency('nokogiri')
  s.add_dependency('addressable')
  s.add_dependency('rspec')
  s.add_dependency('awesome_print')
  s.add_dependency('sinatra')
  s.add_dependency('thin')
  s.add_dependency('haml')

end
