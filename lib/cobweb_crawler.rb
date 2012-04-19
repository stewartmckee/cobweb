require 'digest/md5'
require 'date'
require 'ap'
#require 'namespaced_redis'

class CobwebCrawler
  
  def initialize(options={})
    @options = options
    
    @statistic = {}
    
    @options[:redis_options] = {:host => "127.0.0.1"} unless @options.has_key? :redis_options
    crawl_id = Digest::MD5.hexdigest(DateTime.now.inspect.to_s)
    
    @redis = NamespacedRedis.new(@options[:redis_options], "cobweb-#{crawl_id}")
    
    @cobweb = Cobweb.new(@options)
  end
  
  def crawl(base_url, crawl_options = {}, &block)
    @options[:base_url] = base_url unless @options.has_key? :base_url
    
    @crawl_options = crawl_options
    
    @redis.sadd "queued", base_url
    crawl_counter = @redis.scard("crawled").to_i
    queue_counter = @redis.scard("queued").to_i

    while queue_counter>0 && (@options[:crawl_limit].to_i == 0 || @options[:crawl_limit].to_i > crawl_counter)      
      thread = Thread.new do

        url = @redis.spop "queued"
        crawl_counter = @redis.scard("crawled").to_i
        queue_counter = @redis.scard("queued").to_i
        
        @options[:url] = url
        unless @redis.sismember("crawled", url.to_s)
          begin
            Stats.update_status("Requesting #{url}...")
            content = @cobweb.get(url)
            Stats.update_status("Processing #{url}...")

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
              @statistic[:page_size] = @statistic[:page_size].to_i + content[:length].to_i
            else
              @statistic[:asset_count] = @statistic[:asset_count].to_i + 1
              @statistic[:asset_size] = @statistic[:asset_size].to_i + content[:length].to_i
            end
            
            @statistic[:total_redirects] = 0 if @statistic[:total_redirects].nil?
            @statistic[:total_redirects] += content[:redirect_through].count unless content[:redirect_through].nil?
            
            @statistic[:crawl_counter] = crawl_counter
            @statistic[:queue_counter] = queue_counter
            
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

            @redis.sadd "crawled", url.to_s
            @redis.incr "crawl-counter" 
            
            content[:links].keys.map{|key| content[:links][key]}.flatten.each do |content_link|
              link = content_link.to_s
              unless @redis.sismember("crawled", link)
                puts "Checking if #{link} matches #{@options[:base_url]} as internal?" if @options[:debug]
                if link.to_s.match(Regexp.new("^#{@options[:base_url]}"))
                  puts "Matched as #{link} as internal" if @options[:debug]
                  unless @redis.sismember("crawled", link) || @redis.sismember("queued", link)
                    puts "Added #{link.to_s} to queue" if @options[:debug]
                    @redis.sadd "queued", link
                    crawl_counter = @redis.scard("crawled").to_i
                    queue_counter = @redis.scard("queued").to_i
                  end
                end
              end
            end
            
            crawl_counter = @redis.scard("crawled").to_i
            queue_counter = @redis.scard("queued").to_i
            Stats.update_statistics(@statistic)
            Stats.update_status("Completed #{url}.")
            puts "Crawled: #{crawl_counter.to_i} Limit: #{@options[:crawl_limit].to_i} Queued: #{queue_counter.to_i}" if @options[:debug] 
       
            yield content, @statistic if block_given?

          rescue => e
            puts "!!!!!!!!!!!! ERROR !!!!!!!!!!!!!!!!"
            ap e
            ap e.backtrace
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
