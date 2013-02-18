class String

  # add ends_with? support if method is missing
  def method_missing(m, *args, &block)
    if m == :ends_with?
      suffix = args[0]
      suffix.respond_to?(:to_str) && self[-suffix.length, suffix.length] == suffix
    else
      super
    end
  end
end