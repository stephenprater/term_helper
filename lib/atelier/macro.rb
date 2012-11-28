require 'singleton'
require 'ostruct'
require 'erb'


module MacroMethod
  attr_accessor :memo
end

module Atelier

  class MacroDonkey < BasicObject
    include ::Object::Singleton
    
    def method_missing *_
      ex = ::Object::SyntaxError.new("Any use of the macro's arguments must be within an ERB block.")
      ex.set_backtrace ::Kernel.caller(1)
      ::Kernel.raise ex
    end
  end

  module Macro

    class << self
      def extended base
        base.instance_variable_set(:@memo, {})
      end
    end
    
    def memo name 
      if instance_methods.include?(name) && @memo.has_key?(name)
        @memo[name]
      elsif not instance_methods.include? name
        raise NoMethodError, "undefined method `#{name}' for #{self.inspect}"
      end
    end

    def macro name, &block
      #give our method the 'lambda tricks'
      begin
        temp_method = MacroDonkey.send :define_method, :__temp, &block
      ensure
        MacroDonkey.send(:undef_method, :__temp) rescue $!
      end

      # and then retrieve the parameters with their tricks
      params = temp_method.parameters.group_by do |p|
        p[0]
      end.each_pair.with_object({}) do |(k,v), m|
        m[k] = v.collect { |r| r[1] }
      end

      #set the trace function so that we can look for the default
      #values of the options parameters in the binding of the proc
      #as soon as the eval operation doesn't raise a name error
      #it will terminate (that would be the first line of the proc)
      trace_func = lambda do |*_, binding, klass|
        begin
          throw(:found,(params[:opt].each_with_object({}) do |p,h|
            h[p] = eval(p.to_s, binding)
          end))
        rescue NameError
          nil
        end
      end
     
      default_values = catch :found do
        begin
          set_trace_func trace_func
          temp_method.call(*[].fill(nil,0,params[:req].size))
        ensure
          set_trace_func nil
        end
      end
     
      #get the total number of arguments
      real_arity = [params[:req],params[:opt], params[:rest]].flatten.size

      # call the method again - this time allowing it to complete
      # the donkey class will raise an error if it's used, so it
      # will catch it if one is used not in a deferred string block
      memo = temp_method.call(*[].fill(MacroDonkey.instance, 0, real_arity))
      
      #now you construct the argument string
      params_string = params[:req].join(", ")
      params_string << ", " + params[:opt].collect do |p|
        "#{p} = #{default_values[p]}"
      end.to_a.join(', ')
      params_string << ", *#{params[:rest][0]}" # there's only ever one splat

      self.class_eval do 
        eval <<-EVAL, binding, *block.source_location
        def #{name}(#{params_string})
          ERB.new('#{memo}').result(binding)
        end
        EVAL
      end
      @memo[name ] = memo
    end
  end
end

class Goofball
  extend Atelier::Macro

  macro :whatever do |x, z = 13, y = 12, *args|
    str = ""
    str << "what"
    str << '<%= x.to_s %>'
    str << "ever"
    str << '<%= (z + 13).to_s %>'
  end
end

