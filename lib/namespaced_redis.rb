class NamespacedRedis
  def initialize(redis, namespace="")
    raise "redis must be supplied" if redis.nil?
    @redis = redis
    @namespace = namespace
  end
  
  def sismember(key, member)
    @redis.sismember namespaced(key), member
  end
  
  def sadd(key, value)
    @redis.sadd namespaced(key), value
  end
  
  def get(key)
    @redis.get namespaced(key)
  end
  
  def incr(key)
    @redis.incr namespaced(key)
  end
  
  def exist(key)
    @redis.exist namespaced(key)
  end
  
  def set(key, value)
    @redis.set namespaced(key), value
  end
  
  def del(key)
    @redis.del namespaced(key)
  end
  
  def expire(key, value)
    @redis.expire namespaced(key), value
  end
  
  def namespaced(key)
    "#{@namespace}-#{key}"
  end
  
  def native
    @redis
  end
  
  def namespace
    @namespace
  end
  
end