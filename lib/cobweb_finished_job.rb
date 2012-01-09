class CobwebFinishedJob
  require "ap"
  
  @queue = :cobweb_finished_job

  def self.perform(statistics)
    puts "Dummy Finished Job"

    ap statistics
    
  end
end
