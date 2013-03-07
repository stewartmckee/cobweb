module CobwebDSL

  def scope
    DocumentScope.new(@doc)
  end

  # def method_missing(m, *args, &block)
  #   if m.to_s =~ /^(.*?)_tags$/
  #     tag_name = $1
  #     @doc.search($1)
  #   elsif m.to_s =~ /^(.*?)_tag$/
  #     tag_name = $1
  #     @doc.at($1)
  #   elsif m.to_s =~ /^(.*?)_tags_used\?$/
  #     tag_name = $1
  #     !@doc.search(tag_name).empty?
  #   elsif m.to_s =~ /^(.*?)_tags_with_(.*?)$/
  #     tag_name = $1
  #     attribute_name = $2
  #     attribute_value = "=#{args[0]}" unless args[0].nil?
  #     @doc.search("#{tag_name}[#{attribute_name}#{attribute_value}]")
  #   elsif m.to_s =~ /^(.*?)_tag_with_(.*?)$/
  #     tag_name = $1
  #     attribute_name = $2
  #     attribute_value = "=#{args[0]}" unless args[0].nil?
  #     @doc.at("#{tag_name}[#{attribute_name}#{attribute_value}]")
  #   else
  #     super
  #   end
  # end

end