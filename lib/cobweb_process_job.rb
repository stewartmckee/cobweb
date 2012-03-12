class CobwebProcessJob
  require "ap"
  
  @queue = :cobweb_process_job

  def self.perform(content)
    content = HashHelper.symbolize_keys(content)
    puts "Dummy Processing for #{content[:url]}"

    #ap content.keys
    
  end
end
