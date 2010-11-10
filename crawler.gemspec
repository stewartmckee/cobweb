spec = Gem::Specification.new do |s|
  s.name              = "cobweb"
  s.version           = "0.0.11"
  s.author            = "Stewart McKee"
  s.email             = "stewart@weare6central.com"
  s.homepage          = "http://github.com/6central/cobweb"
  s.platform          = Gem::Platform::RUBY
  s.summary           = "Crawler utilizing resque"
  s.files             = Dir["{spec,lib}/**/*"].delete_if { |f| f =~ /(rdoc)$/i }
  s.require_path      = "lib"
  s.has_rdoc          = false
  s.extra_rdoc_files  = ["README.textile"]
  s.add_dependency('resque')
  s.add_dependency('absolutize')
  s.add_dependency('nokogiri')

end
