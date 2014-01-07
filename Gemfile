source 'http://rubygems.org'

gemspec

gem 'rake'
gem 'redis'
gem 'resque'
gem 'awesome_print'
gem 'nokogiri'
gem 'addressable'
gem 'json'
gem 'sinatra'
gem 'haml'
gem 'namespaced_redis', ">=1.0.2"

gem 'redis-namespace'
gem 'rspec'
gem 'rspec-core'
gem 'mock_redis'
gem 'slop'

group :test do
  if ENV["TRAVIS_RUBY_VERSION"].nil?
    gem 'thin', :require => false
  end
  gem 'coveralls', :require => false
end