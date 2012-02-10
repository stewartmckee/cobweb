class CobwebCrawler
  
  def initialize(options={})
    @options = options
    
    @statistic = {}
    @queue = []
    @crawled = []
    
    @cobweb = CobWeb.new(@options)
  end
  
  def crawl(base_url, crawl_options = {}, &block)
    @options[:base_url] = base_url unless @options.has_key? :base_url
    
    @crawl_options = crawl_options
    
    @absolutize = Absolutize.new(@options[:base_url], :output_debug => false, :raise_exceptions => false, :force_escaping => false, :remove_anchors => true)
    
    crawl_counter = @crawled.count
    
    @queue << base_url
    
    while !@queue.empty? && (@options[:crawl_limit].to_i == 0 || @options[:crawl_limit].to_i > crawl_counter)
      
      thread = Thread.new do
        url = @queue.first
        @options[:url] = url
        unless @crawled.include?(url) || url =~ /\/(.+?)\/\1\/\1/      
          begin
            content = @cobweb.get(@options[:url])

            if @statistic[:average_response_time].nil?
              @statistic[:average_response_time] = content[:response_time].to_f
            else
              @statistic[:average_response_time] = (((@statistic[:average_response_time] * crawl_counter) + content[:response_time].to_f) / (crawl_counter + 1))
            end
      
            @statistic[:maximum_response_time] = content[:response_time] if @statistic[:maximum_response_time].nil? || @statistic[:maximum_response_time] < content[:response_time]
            @statistic[:minimum_response_time] = content[:response_time] if @statistic[:minimum_response_time].nil? || @statistic[:minimum_response_time] > content[:response_time]
      
            if @statistic[:average_length]
              @statistic[:average_length] = (((@statistic[:average_length].to_i*crawl_counter) + content[:length].to_i) / (crawl_counter + 1))
            else
              @statistic[:average_length] = content[:length].to_i
            end
      
            @statistic[:maximum_length] = content[:length].to_i if @statistic[:maximum_length].nil? || content[:length].to_i > @statistic[:maximum_length].to_i
            @statistic[:minimum_length] = content[:length].to_i if @statistic[:minimum_length].nil? || content[:length].to_i < @statistic[:minimum_length].to_i
            @statistic[:total_length] = @statistic[:total_length].to_i + content[:length].to_i

            if content[:mime_type].include?("text/html") or content[:mime_type].include?("application/xhtml+xml")
              @statistic[:page_count] = @statistic[:page_count].to_i + 1
              @statistic[:page_size] = @statistic[:page_count].to_i + content[:length].to_i
            else
              @statistic[:asset_count] = @statistic[:asset_count].to_i + 1
              @statistic[:asset_size] = @statistic[:asset_count].to_i + content[:length].to_i
            end

            mime_counts = {}
            if @statistic.has_key? :mime_counts
              mime_counts = @statistic[:mime_counts]
              if mime_counts.has_key? content[:mime_type]
                mime_counts[content[:mime_type]] += 1
              else
                mime_counts[content[:mime_type]] = 1
              end
            else
              mime_counts = {content[:mime_type] => 1}
            end
            @statistic[:mime_counts] = mime_counts

            status_counts = {}
          
            if @statistic.has_key? :status_counts
              status_counts = @statistic[:status_counts]
              if status_counts.has_key? content[:status_code].to_i
                status_counts[content[:status_code].to_i] += 1
              else
                status_counts[content[:status_code].to_i] = 1
              end
            else
              status_counts = {content[:status_code].to_i => 1}
            end
            @statistic[:status_counts] = status_counts

            @crawled << url
            crawl_counter += 1
            @queue.delete(url)
            content[:links].keys.map{|key| content[:links][key]}.flatten.each do |link|
              unless @crawled.include? link
                puts "Checking if #{link} matches #{@options[:base_url]} as internal?" if @options[:debug]
                if link.to_s.match(Regexp.new("^#{@options[:base_url]}"))
                  puts "Matched as #{link} as internal" if @options[:debug]
                  unless @crawled.include? link.to_s or @queue.include? link.to_s
                    puts "Added #{link.to_s} to queue" if @options[:debug] 
                    @queue << link.to_s
                  end
                end
              end
            end
            @queue.uniq!
            
            puts "Crawled: #{crawl_counter} Limit: #{@options[:crawl_limit]} Queued: #{@queue.count}" if @options[:debug]
          
            yield content if block_given?

          rescue => e
            puts "!!!!!!!!!!!! ERROR !!!!!!!!!!!!!!!!"
            ap e
            @queue.delete(url)
          
          end
        else
          puts "Already crawled #{@options[:url]}" if @options[:debug]
        end
      end
      thread.join
    end
    @statistic
  end
  
end