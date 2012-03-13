## add symbolize methods to hash
class HashUtil
  def self.symbolize_keys
    keys.each do |key|
      if key.instance_of? String
        value = self[key]
        self.delete(key)
        self[key.to_sym] = value        
      end
    end
    self
  end  
  def self.deep_symbolize_keys(h)
    h.symbolize_keys
    h.keys.each do |key|
      if h[key].instance_of? Hash
        h[key].deep_symbolize_keys
      end
    end
    h
  end
end