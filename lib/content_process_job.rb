class ContentProcessJob
  require "ap"
  
  @queue = :cobweb_process_job

  def self.perform(content)
    content.symbolize_keys 
    puts "Dummy Processing for #{content[:url]}"

    #ap content.keys
    
  end
end