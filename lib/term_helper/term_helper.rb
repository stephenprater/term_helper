require 'singleton'
require 'pry'
require 'forwardable'

module TermHelper
  class CommandCache
    # assemble format strings for movement commands
    movmts = Hash[[:hpa,:vpa,:cup,:home,:setaf].zip(
      [`tput hpa`, `tput vpa`, `tput cup`,`tput home`].collect do |fmt|
      fmt.split(/(%[pPg][\d\w])|(%.)/).each_with_object '' do |i,m|
        if i == '%d'
          m << '%d'
        elsif i[0] != '%'
          m << i
        end
      end
    end)]
    
    setaf = `tput setaf`.split(/(%.*?(?=%)|;)/)
    setaf = "#{setaf[0]}%s#{setaf[-1]}"
    
    setab = `tput setab`.split(/(%.*?(?=%)|;)/)
    setab = "#{setab[0]}%s#{setab[-1]}"

    COLOR_LIST = {
      black: 0,
      red: 1,
      green: 2,
      yellow: 3,
      blue: 4,
      magenta: 5,
      cyan: 6,
      white: 7,
      gray: 8,
      bold_red: 9,
      bold_green: 10,
      bold_yellow: 11,
      bold_blue: 12,
      bold_magenta: 13,
      bold_cyan: 14,
      bold_white: 15
    }

    #These commands have well defined output for a given terminal, so
    #we cache the strings in order to not call tput on every command
    COMMANDS = {
    clear_all: `tput clear`,
    save: `tput sc`,
    restore: `tput rc`,
    reset: `tput sgr0`,
    smacs: `tput smacs`,
    symbols: :smacs, 
    rmacs: `tput rmacs`,
    alpha: :rmacs, 
    left: `tput cub1`,
    right: `tput cuf1`,
    up: `tput cuu1`,
    down: `tput cud1`,
    clear_line: `tput el`,
    clear_screen: `tput ed`,
    clear_backward: `tput el1`,
    row: lambda do |row|
      movmts[:vpa] % row
    end,
    column: lambda do |col|
      movmts[:hpa] % col
    end,
    setab: lambda do |color|
      color = color.is_a?(Symbol) ? COLOR_LIST[color] : color
      str = ""
      if color < 8
        str = "4#{color}"
      elsif color < 16
        str = "10#{color}"
      else 
        str = "48;5;#{color}"
      end
      setab % str
    end,
    background: :setab,
    setaf: lambda do |color|
      color = color.is_a?(Symbol) ? COLOR_LIST[color] : color
      str = ""
      if color < 8
        str = "3#{color}"
      elsif color < 16
        str = "9#{color-8}"
      else
        str = "38;5;#{color}"
      end
      setaf % str 
    end,
    foreground: :setaf,
    mrcup: lambda do |row,col|
      hdir = col > 0 ? :right : :left
      vdir = row > 0 ? :down : :up 
      [[vdir,row],[hdir,col]].inject '' do |memo, dir|
        memo << (COMMANDS[dir[0]] * dir[1].abs)
      end
    end,
    move_relative: :mrcup,
    moveto: lambda do |*args|
      # pass it either a [row,col] array or a row:x, col:x opts hash
      row,col = *({ :row => nil, :col => nil}.merge(args.first).values rescue args)
      cmd = (col and row) ? :cup : (col ? :hpa : (row ? :vpa : :home))
      movmts[cmd] % ([row, col].compact)
    end
    }
    COMMANDS.each_pair do |meth,b|
      if b.is_a?(Symbol) and self.respond_to? b
        alias_method meth, b
      else
        begin
          c = b.is_a?(Proc) ? b : lambda { b }
          define_method meth, &c
        rescue ArgumentError => e
          puts e
          raise
        end
      end
    end
  end
  
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

  def uniq_id 
    @uniq_id ||= "#{"%x" % (Time.now.to_i + self.__id__).hash}".upcase
  end

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
    {:rows => `tput lines`.chomp.to_i, :cols => `tput cols`.chomp.to_i }
  end

  # Save the current position of the cursor, draw some stuff,
  # then return the current positin of the cursor. an exception
  # is raised if there and backs are nested within each other.
  def there_and_back
    raise "nested there_and_back" if @within
    _within = true
    output do |str|
      str << c.save 
      yield(str)
      str << c.restore
    end
    _within = false
  end

  def char_set set
    output do |str|
      str << _last_set.push(set).last
      yield(str)
      str << (_last_set.tap { |c| c.pop }.last || (c.reset + _last_color.last.to_s)) 
    end
  end
  private :char_set

  # Render symbols within the provided block
  def symbol arg = nil, &block
    if block and not arg
      char_set c.smacs, &block 
    elsif arg and not block
      _last_set.last == c.rmacs ? "#{c.smacs}#{arg.to_s}#{c.rmacs}" : arg.to_s 
    else
      raise "couldn't determine current character set"
    end
  end
  alias :symbols :symbol

  def alpha arg = nil, &block
    if block and not arg
      char_set c.rmacs, &block 
    elsif arg and not block
      _last_set.last == c.smacs ? "#{c.rmacs}#{arg.to_s}#{c.smacs}" : arg.to_s 
    else
      raise "couldn't determine current character set"
    end
  end
  alias :alphas :alpha

  def ol_macro name, arr = nil, &block
    string = ""
    if block_given?
      string = yield
    elsif arr
      string = arr.inject "" do |c| 
        self.__send__ *c
      end
    end
    @cache.define_singleton_method(name) { string }
  end
  private :ol_macro

  def fl_macro name, &block
    raise ArgumentError "Function like macros require a block" if block.nil?
    # we need to retrieve the proc source, then replace each occurence of any arguments
    # with the subsitition we can identify in the subsequent command string.
    # then, we can do simple substitition on the memoized macro string
    file, line = block.source_location
    File.open(file) do |f|
      lines = f.each_line
      (line - 1).times { lines.next }
      raise "no macro at location #{file}, #{line}" unless ident = lines.next.match(/macro/).try(:begin,0)
      macro_string = lines.each_with_object "" do |line, memo|
        break memo if line.match(/end/).try(:begin,0) == ident
        memo << line 
      end
      args = block.parameters.collect do |arg|
        (arg[0] == :rest) ? (raise "Macros cannot accomodate splat parameters") : arg[1]
      end
      regex = /(self.*?[ )\n;])|(?:(?:[ (])((?:#{args.map(&:to_s).join('|')}).*?)[ ()\n])/
      #rewrite each line of the macro to sub in any arguments
      rewritten = macro_string.lines.each_with_object "" do |line,memo|
        line.scan(regex).entries.each do |match|
          mtr = match[0] || match[1]
          line.gsub!(mtr,'\'#{' + mtr +'}\'')
        end
        memo << line
      end
      # create the macro string
      macro_string = eval(rewritten, block.binding)
      @cache.instance_eval do
        eval(<<-DEF, binding, file, line)
          def #{name}(#{args.join(", ")})
            \"#{macro_string}\"
          end
        DEF
      end
    end
  end
  private :fl_macro
  
  # Memoize a sequence of commands as a string. 
  # You can create either simple macros, which are just a list of commands
  # or function like macros, which take arguments. Note that these function
  # like macros are NOT FUNCTIONS. You can't operate on the values passed
  # into a function-like macro, you have to use it basically as it comes in.
  # A good rule of thumb, if you're sending a message to a parameter to get
  # a different value which you want to do something else with, you want to
  # use #widget and not macro.
  # a good use of a macro: drawing the name of your program in ascii art.
  # a bad use of a macro: a progress bar.
  def macro name, arr = nil, &block
    if (not block.nil? and arr) or (block.nil? and not arr)
      raise ArgumentError "Array of commands or a block required."
    end
    
    if block.arity > 0
      fl_macro name, &block
    else
      if arr
        ol_macro name, arr
      elsif not block.nil?
        ol_macro name, &block
      end
    end
  end
  
  # define a singleton method on the object which includes term_helper
  # it can also define a s
  def widget name, &block
    if name.is_a? Symbol and block_given?
      self.define_singleton_method(name, &block)
    elsif name.respond_to? :block
      self.define_singleton_method(name.name, &name.block)
    end
  end

  attr_reader :cache
  alias :c :cache

  def build_cache
    @cache = CommandCache.new
    owner = self
    @cache.define_singleton_method :method_missing do |method, *args, &block|
      if owner.respond_to? method
        owner.send method, *args, &block
      else
        raise NoMethodError, "couldn't fine #{method} in cache or object"
      end
    end
  end
  private :build_cache

  extend Forwardable

  # these are module level items so that more than
  # one atelier can draw on the screen at a time
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
    
    ObjectSpace.define_finalizer(TermHelper, TermHelper.remove_tempfile())
  end
end

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

class TermHelper::Widget
  attr_reader :block, :name
  def initialize name, &block
    @block = block
    @name = name
  end
end

TermHelper::Widget.new :window do |row,col, width, height, opts = {}|
  opts = {:color => false, :noblank => false}.merge(opts)
  str = there_and_back do |str|
    str << c.setaf(opts[:color]) if opts[:color]
    str << c.moveto(row,col)
    str << smacs { 'm'+('q' * width)+'j' }
    str << c.mrcup(0, -(width + 2))
    (height-2).times do
      str << c.mrcup(-1,0)
      str << smacs { 'x' }
      if opts[:noblank]
        str << c.mrcup(0,width)
      else
        str << ' ' * width
      end
      str << smacs { 'x' }
      str << c.mrcup(0,-(width + 2))
    end
    str << smacs { 'l' + ('q' * width) + 'k'}
    str << c.reset
    if block_given?
      str << c.mrcup(1,0)
      string = (yield).scan(/.{0,#{width}}/)
      string = string.length > rows ? string[0..rows] : string
      string.each do |l|
        str << c.mrcup(0,col)
        str << l + "\n"
      end
    end
  end
end

    

