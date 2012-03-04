## add symbolize methods to hash
class Hash
  def symbolize_keys
    keys.each do |key|
      if key.instance_of? String
        value = self[key]
        self.delete(key)
        self[key.to_sym] = value        
      end
    end
    self
  end  
  def deep_symbolize_keys
    symbolize_keys
    keys.each do |key|
      if self[key].instance_of? Hash
        self[key].deep_symbolize_keys
      end
    end
    self
  end
end