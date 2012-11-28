module TermHelper
  class Widget
    attr_reader :block, :name
    def initialize name, &block
      @block = block
      @name = name
    end
  end
end
