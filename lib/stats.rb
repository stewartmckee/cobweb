require 'bundler/setup'
require 'sinatra'
require 'haml'

class Stats < Sinatra::Base
  
  def self.update_statistics(statistics)
    @@statistics = statistics
  end
  
  def self.update_status(status)
    @@status = status
  end
  
  ap settings.root
  set :views, settings.root + '/../views'
  
  get '/' do
    @statistics = @@statistics
    @status = @@status
    haml :statistics
  end
  
end

thread = Thread.new do
  Stats.run!
  
  ## we need to manually kill the main thread as sinatra traps the interrupts
  Thread.main.kill
end

