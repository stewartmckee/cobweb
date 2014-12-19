class Cobweb
  module ClassHelper

    # class name to actual class
    # Cobweb::ClassHelper.resolve_class
    def self.resolve_class class_name
      modules_with_class = class_name.split('::')
      first_const = const_get modules_with_class.shift
      modules_with_class.inject(first_const) do |current_const,next_part|
        current_const.const_get next_part
      end
    end

  end
end