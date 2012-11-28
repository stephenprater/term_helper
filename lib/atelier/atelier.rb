require 'forwardable'
require 'securerandom'
require 'monitor'

require 'atlier/symbol_table'

module Atelier
  class CursorRecursionException < StandardError; end
  class CharacterSetException < StandardError
    def message
      "Couldn't determine current character set"
    end
  end
  
  @@monitor = Monitor.new

  #Output to a string given as an argument, to an empty string if no argument
  #is given, or to an IO if one is given. In the case of the IO the output
  #is not written until the entire string is built.  In the case of
  #a string, the string is modified in place.
  #in all cases, the method returns it's output string
  def output string = nil 
    if string.is_a? IO
      to_io = true
      dest = string
      string = ""
    else
      string = "" unless string.respond_to? :<<
    end
   
    yield(string) if block_given? # modifiy str in place
    
    if to_io
      dest << string
    end
    string
  end

  #generates a unique id for the term helper in each process
  def uniq_id
    @uniq_id ||= SecureRandom.uuid.gsub(/-/,'')
  end


  # A disgusting hack which returns the current cursor position
  def current_position
    unless _temp_file 
      system "mkfifo /tmp/#{self.class}_#{uniq_id}"
      _temp_file = File.open("/tmp/#{self.class}_#{uniq_id}","w+")
    end  

    #taking bids for a better implementation of this
    system("stty -echo; tput u7; read -d R x; stty echo; echo ${x#??} >> #{_temp_file.path}")
    _temp_file.gets.chomp.split(';').map(&:to_i)
  end
 
  # Output the results of the block in the color provided, which
  # can be an integer, or a named color up to sixteen
  def color color
    output do |str|
      str << _last_color.push(c.setaf(color)).last
      yield(str)
      str << (_last_color.tap { |c| c.pop }.last || (c.reset + _last_set.last.to_s))
    end
  end

  # Return the current size of the terminal window
  def size
    { :rows => TermInfo.screen_lines, :cols => TermInfo.screen_columns }
  end

  # Save the current position of the cursor, draw some stuff,
  # then return the current positin of the cursor. an exception
  # is raised if there and backs are nested within each other.
  def there_and_back
    raise CursorRecursionException, "Cursor position cannot be saved again before restoring" if @within
    @@monitor.synchronize { self._within = true }
    output do |str|
      str << c.save 
      yield(str)
      str << c.restore
    end
    @@monitor.synchronize { self._within = false }
  end
  alias :draw_and_return :there_and_back

  def char_set set
    output do |str|
      @@monitor.synchronize { str << _last_set.push(set).last }
      yield(str)
      @@monitor.synchronize do
        str << (_last_set.tap { |c| c.pop }.last || (c.reset + _last_color.last.to_s))
      end
    end
  end
  private :char_set

  def method_missing_with_symbol_lookup meth, *args, &block
    SymbolTable.__send__(:symbol_lookup, meth) || method_missing_without_symbol_lookup(meth, *args, &block)
  end

  # Render symbols within the provided block
  def symbol arg = nil, &block
    if block and not arg
      alias_method :method_missing_without_symbol_lookup, :method_missing
      alias_method :method_missing, :method_missing_with_symbol_lookup
      char_set c.smacs, &block 
    elsif arg and not block
      if arg.is_a? Symbol
        _last_set.last == c.rmacs ? "#{c.smacs}#{self.send arg}#{c.rmacs}" : arg.to_s 
      else
        _last_set.last == c.rmacs ? "#{c.smacs}#{arg.to_s}#{c.rmacs}" : arg.to_s
      end
    else
      raise CharacterSetException
    end
  ensure
    alias_method :method_missing, :method_missing_without_symbol_lookup
  end
  alias :symbols :symbol

  def alpha arg = nil, &block
    if block and not arg
      char_set c.rmacs, &block 
    elsif arg and not block
      _last_set.last == c.smacs ? "#{c.rmacs}#{arg.to_s}#{c.smacs}" : arg.to_s 
    else
      raise CharacterSetException
    end
  end
  alias :alphas :alpha

  def simple_macro name, arr = nil, &block
    string = ""
    if block_given?
      string = yield
    elsif arr
      string = arr.inject "" do |c| 
        self.__send__(*c)
      end
    end
    @cache.define_singleton_method(name) { string }
  end
  private :simple_macro

  def function_macro name, &block
    raise ArgumentError "Function like macros require a block" if block.nil?
    string = ""
    parameter_list = []
    block.parameters.each_with_index do |sub_list,idx|
      if sub_list[0] == :args
        raise ArgumentError "Function like macros do not support argument splats"
      else
        parameter_list << "<%= #{sub_list[1]} %>"
      end
    end
    string = yield
    @cache.define_singleton_method(name) do
      ERB.new(string).result(block.binding)
    end
  end
  private :function_macro
  
  # Memoize a sequence of commands as a string. 
  # You can create either simple macros, which are just a list of commands
  # or function like macros, which take arguments. Note that these function
  # like macros are NOT FUNCTIONS. You can't operate on the values passed
  # into a function-like macro, you have to use it basically as it comes in.
  # A good rule of thumb, if you're sending a message to a parameter to get
  # a different value which you want to do something else with, you want to
  # use #widget and not macro.
  # a good use of a simple macro: drawing the name of your program in ascii art.
  # a good use of a function macro: a progress bar
  # a bad use of a macro: windows or areas with dynamic content 
  def macro name, arr = nil, &block
    if (not block.nil? and arr) or (block.nil? and not arr)
      raise ArgumentError "Array of commands or a block required."
    end
    
    if block.arity > 0
      function_macro name, &block
    else
      if arr
        simple_macro name, arr
      elsif not block.nil?
        simple_macro name, &block
      end
    end
  end
  
  # define a singleton method on the object which includes term_helper
  # it can also define
  def widget name, &block
    if name.is_a? Symbol and block_given?
      self.define_singleton_method(name, &block)
    elsif name.respond_to? :block
      self.define_singleton_method(name.name, &name.block)
    end
  end

  attr_reader :cache
  alias :c :cache

  extend Forwardable
  
  # these are module level items so that more than
  # one atelier can draw on the screen at a time
  # the amount to global state for anything that includes
  # the atelier module
  @_last_set = []
  @_last_color = []
  @_within = false
  @_temp_file = nil
  @cache = CommandCache.new # the default command cache
  
  def_delegators :TermHelper, :_last_color, :_last_set, :_within, :_temp_file 

  class << self
    attr_accessor :_last_color, :_last_set, :_within, :_temp_file 

    def remove_tempfile
      if @_temp_file
        proc { system "rm #{@_temp_file.path}"; } 
      else
        proc { }
      end
    end

    def cache
      @cache
    end

    def included owner 
      owner.instance_eval do
        @cache = CommandCache.new self
      end
    end
    
    ObjectSpace.define_finalizer(TermHelper, TermHelper.remove_tempfile())
  end
end
