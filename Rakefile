require 'rubygems'
require 'resque/tasks'
require 'rspec/core/rake_task'
require [File.dirname(__FILE__), "lib", "cobweb"].join("/") 

task :default => :spec
 
RSpec::Core::RakeTask.new do |t|
  t.pattern = "./spec/**/*_spec.rb" # don't need this, it's default.
  # Put spec opts in a file named .rspec in root
end