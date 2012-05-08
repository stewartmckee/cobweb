# Dummy resque job that executes at the end of the crawl if none are specified
class CobwebFinishedJob
  require "ap"
  
  @queue = :cobweb_finished_job

  # perform method for resque to execute
  def self.perform(statistics)
    puts "Dummy Finished Job"

    ap statistics
    
  end
end
