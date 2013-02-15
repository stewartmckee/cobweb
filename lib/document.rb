class DocumentScope

  @context = nil

  def method_missing(m, *args, &block)
    if m.to_s =~ /^(.*?)_tags$/
      tag_name = $1
      @context = @context.search($1) if @context
      self
    elsif m.to_s =~ /^(.*?)_tag$/
      tag_name = $1
      @context = @context.at($1) if @context
      self
    elsif m.to_s =~ /^(.*?)_tags_with_(.*?)$/
      tag_name = $1
      attribute_name = $2
      attribute_value = "=#{args[0]}" unless args[0].nil?

      selector = "#{tag_name}[#{attribute_name}#{attribute_value}]"
      @context = @context.search(selector) if @context
      self
    elsif m.to_s =~ /^(.*?)_tag_with_(.*?)$/
      tag_name = $1
      attribute_name = $2
      attribute_value = "='#{args[0]}'" unless args[0].nil?
      selector = "#{tag_name}[#{attribute_name}#{attribute_value}]"
      @context = @context.at(selector) if @context
      self
    else
      super
    end
  end

  def initialize(body)
    @context = Nokogiri::HTML.parse(body)
  end

  def each(&block)
    @context.each(&block)
  end

  def map(&block)
    @context.map(&block)
  end

  def select(&block)
    @context.select(&block)
  end

  def [](value)
    @context ? @context[value] : ""
  end

  def contents
    @context ? @context.text.gsub("\n","") : ""
  end
  alias :text :contents

  def count
    @context ? @context.count : 0
  end
  def to_s
    @context ? @context.to_s.gsub("\n","") : ""
  end

end