## add symbolize methods to hash
class HashHelper
  def self.symbolize_keys(hash)
      hash.keys.each do |key|
        if key.instance_of? String
          value = hash[key]
          hash.delete(key)
          hash[key.to_sym] = value
        end
      end
      hash
    end
    def self.deep_symbolize_keys(hash)
      hash = symbolize_keys(hash)
      hash.keys.each do |key|
        if hash[key].instance_of? Hash
          hash[key]= deep_symbolize_keys(hash[key])
        end
      end
      hash
    end
end