class ExportCommand

  require 'yaml'

  def self.start(opts, path)

    uri = URI.parse(opts[:url])
    default_root_path = File.join(Dir.pwd, uri.host)

    options = {
      :cache => 600,
      :crawl_limit => 1000000,
      :raise_exceptions => true,
      :root_path => default_root_path
    }.merge(opts)
    


    statistics = CobwebCrawler.new(options).crawl(options[:url]) do |page|
      begin
        puts "Just crawled #{page[:url]} and got a status of #{page[:status_code]}."

        uri = URI.parse(page[:url])

        path = ""

        Dir.mkdir(options[:root_path]) unless File.exist?(options[:root_path])

        uri.path.split("/")[0..-2].each do |dir|
          path+="/" unless path.ends_with?("/")
          path+=dir 
          if File.exist?(options[:root_path] + path) && !File.directory?(options[:root_path] + path)
            FileUtils.mv(options[:root_path] + path, options[:root_path] + path + ".tmp")
            Dir.mkdir(options[:root_path] + path)
            FileUtils.mv(options[:root_path] + path + ".tmp", options[:root_path] + path + "/index.html")
          else
            Dir.mkdir(options[:root_path] + path) unless Dir.exist?(options[:root_path] + path)
          end
        end
        path += "/" unless path.ends_with?("/")
        filename = uri.path.split("/")[-1]
        if filename.nil? || filename.empty?
          filename = "index.html"
        end
        filename = filename + "_" + uri.query.gsub("/", "%2F") unless uri.query.nil?

        if page[:text_content]
          doc = Nokogiri::HTML.parse(page[:body])

          if doc.search("title").first
            title = doc.search("title").first.content.gsub(" - ", " ") 
          else
            title = uri.path.split("/")[-1]
          end
          page[:description] = doc.search("meta[name=description]").first.content if doc.search("meta[name=description]").first
          page[:keywords] = doc.search("meta[name=keywords]").first.content if doc.search("meta[name=keywords]").first
          page[:meta_title] = doc.search("meta[name=title]").first.content if doc.search("meta[name=title]").first

          body = page[:body]

          File.open(options[:root_path] + path + filename, "w+"){|f| f.write(page.to_yaml)}

          #puts "Spree::Page.create!(:title => #{title}, :body => #{body}, :visible => #{true}, :meta_keywords => #{keywords}, :meta_description => #{description}, :layout => "", :meta_title => #{meta_title})"
          #Spree::Page.create!(:title => title, :body => body, :visible => false, :meta_keywords => keywords, :meta_description => description, :layout => "", :meta_title => meta_title)
        else
          File.open(options[:root_path] + path + filename, "wb"){|f| f.write(Base64.decode64(page[:body]))}
        end

        puts "Finished Crawl with #{statistics[:page_count]} pages and #{statistics[:asset_count]} assets." if statistics
      rescue => e
        puts e.message
        puts e.backtrace
      end
    end

  end
end