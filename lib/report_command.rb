class ReportCommand
  def self.start(opts)

    if opts[:output]
      options = opts.to_hash.delete_if { |k, v| v.nil?}
      options[:quiet] = !opts[:verbose]

      if options.has_key?(:seed_url_file)
        filename = options.delete(:seed_url_file)
        options[:seed_urls] = []
        File.open(filename, "r") do |f|
          f.each_line do |line|
            options[:seed_urls] << line
          end
        end
      end

      @crawler = CobwebCrawler.new({:cache_type => :full, :raise_exceptions => true}.merge(options))

      columns = nil

      CSV.open(options[:output], "wb", :force_quotes => true) do |csv|

        statistics = @crawler.crawl(options[:url]) do |page|
          puts "Reporting on #{page[:url]}"
          @doc = page[:body]
          page["link_rel"] = scope.link_tag_with_rel("canonical")["href"]
          page["title"] = scope.head_tag.title_tag.contents
          page["description"] = scope.meta_tag_with_name("description")["content"]
          page["keywords"] = scope.meta_tag_with_name("keywords")["content"]
          page["img tag count"] = scope.img_tags.count
          page["scripts in body"] = scope.body_tag.script_tags.count
          page["img without alt count"] = scope.img_tags.select{|node| node[:alt].nil? || node[:alt].strip().empty?}.count
          page["img alt"] = scope.img_tags_with_alt.map{|node| node[:alt]}.uniq

          if !columns
            columns = page.keys.reject{|k| k==:body || k==:links}
            csv << columns.map{|k| k.to_s}
          end
          csv << columns.map{|k| page[k]}
        end
      end
    end
  end
end