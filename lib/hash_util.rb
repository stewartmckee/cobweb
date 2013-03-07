# Collection of utility methods for the Hash object
class HashUtil
  
  # Returns a hash with the keys converted to symbols
  def self.deep_symbolize_keys(hash)
    raise "Cannot symbolize keys for a nil object" if hash.nil?
    hash.keys.each do |key|
      value = hash[key]
      hash.delete(key)
      hash[key.to_sym] = value
      if hash[key.to_sym].instance_of? Hash
        hash[key.to_sym] = HashUtil.deep_symbolize_keys(hash[key.to_sym])
      end
    end
    hash
  end
end