module TermHelper
  class TermPainter
    include Singleton
    include TermHelper

    @cache = CommandCache.new
    def self.cache
      @cache
    end

    def self.draw &block
      self.instance.draw &block
    end

    def c
      self.class.cache
    end

    undef :build_cache rescue nil
     
    def draw 
      buffer = ""
      yield buffer, self 
      STDOUT.print(buffer)
    end

    def method_missing method, *args, &block
      if c.respond_to? method
        c.send method, *args, &block
      else
        raise NoMethodError, "#{method} not defined."
      end
    end
  end
end
