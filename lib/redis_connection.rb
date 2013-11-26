class RedisConnection

  @@redis_connections = {}

  def initialize(options={})
    key = options.keys.sort.map{|k| "#{k}:#{options[k]}"}.join(",")
    unless @@redis_connections.has_key?(key)
      @@redis_connections[key] = Redis.new(options)
    end
    @current_connection = @@redis_connections[key]
    @current_connection
  end

  def method_missing(m, *args, &block)
    if @current_connection.respond_to?(m)
      @current_connection.send(m, *args)
    else
      super
    end
  end


end
