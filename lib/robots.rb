# Robots retrieves and processes the robots.txt file from the target server
class Robots
  
  # Processes the robots.txt file
  def initialize(options)
    @options = options
    raise "options should be a hash" unless options.kind_of? Hash
    raise ":url is required" unless @options.has_key? :url
    @options[:file] = "robots.txt" unless @options.has_key? :file
    @options[:user_agent] = "cobweb" unless @options.has_key? :user_agent
    
    uri = URI.parse(@options[:url])
    content = Cobweb.new(:cache => nil, :text_mime_types => ["text/html", "application/xhtml+xml", "text/plain"]).get([uri.scheme, "://", uri.host, ":", uri.port, "/", @options[:file]].join)
    if content[:mime_type][0..4] == "text/"
      @raw_data = parse_data(content[:body])
      
      if @options.has_key?(:user_agent) && @raw_data.has_key?(@options[:user_agent].to_s.downcase.to_sym)
        @params = @raw_data[@options[:user_agent].to_s.downcase.to_sym]
      else
        raise "Wildcard user-agent is not present" unless @raw_data.has_key? :*
        @params = @raw_data[:*]
      end
    else
      raise "Invalid mime type: #{content[:content_type]}"
    end
  end
  
  def allowed?(url)
    uri = URI.parse(url)
    @params[:allow].each do |pattern|
      return true if uri.path.match(escape_pattern_for_regex(pattern))
    end
    @params[:disallow].each do |pattern|
      return false if uri.path.match(escape_pattern_for_regex(pattern))
    end
    true
  end
  
  def user_agent_settings
    @params
  end
  
  def contents
    @raw_data
  end
  
  private
  # escapes characters with meaning in regular expressions and adds wildcard expression
  def escape_pattern_for_regex(pattern)
    pattern = pattern.gsub(".", "\\.")
    pattern = pattern.gsub("?", "\\?")
    pattern = pattern.gsub("*", ".*?")
    pattern
  end
  
  def parse_data(data)
    user_agents = {}
    lines = data.split("\n")
    lines.map!{|line| line.strip}
    lines.reject!{|line| line == "" || line[0] == "#"}
    current_user_agent = nil
    
    lines.each do |line|
      if line[0..10].downcase == "user-agent:"
        current_user_agent = line.split(":")[1..-1].join.downcase.strip.to_sym
        user_agents[current_user_agent] = {:allow => [], :disallow => []}
      else
        if current_user_agent
          values = line.split(":")
          unless values[1..-1].join.strip == ""
            user_agents[current_user_agent][values[0].downcase.strip.to_sym] = [] unless user_agents[current_user_agent].has_key? values[0].downcase.to_sym
            user_agents[current_user_agent][values[0].downcase.strip.to_sym] << values[1..-1].join.strip
          end
        end
      end
    end
    user_agents
  end
end