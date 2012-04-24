class EncodingSafeProcessJob

  @queue = :encoding_safe_process_job

  def self.perform(content)
    clazz = const_get(content["processing_queue"])
    content["body"] = Base64.decode64(content["body"])
    clazz.perform(content)
  end
end



