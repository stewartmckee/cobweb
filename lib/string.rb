class String

  def cobweb_ends_with?(val)
    suffix = val
    suffix.respond_to?(:to_str) && self[-suffix.length, suffix.length] == suffix
  end
end
