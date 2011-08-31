require 'singleton'

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
    clear_screen: `tput clear`,
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

    attr_accessor :default_color

    def initialize options = {} 
      options.reverse_merge!({
        :color => 2
      })
      @default_color = options[:color]
    end

  end
  
  attr_reader :cache


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
    #taking bids for a better implementation of this
    unless @temp_file 
      system "mkfifo /tmp/#{self.class}_#{uniq_id}"
      @temp_file = File.open("/tmp/#{self.class}_#{uniq_id}","w+")
      ObjectSpace.define_finalizer(self, TermHelper.remove_tempfile(@temp_file.path)) 
    end 

    system("stty -echo; tput u7; read -d R x; stty echo; echo ${x#??} >> #{@temp_file.path}")
    @temp_file.gets.chomp.split(';').map(&:to_i)
  end
 
  # you should not need to call this function.  It is called by the ObjectSpace finalizer to delete
  # the position file when the TermHelper is garbage collected
  def remove_tempfile(path)
    proc { system "rm #{path}"; } 
  end
  module_function :remove_tempfile

  # Output the results of the block in the color provided, which
  # can be an integer, or a named color up to sixteen
  def color color
    @_last_color ||= []
    output do |str|
      str << c.setaf(@_last_color.push(color).last)
      yield(str)
      str << c.setaf(@_last_color.tap {|c| c.pop }.last || c.default_color )
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
    @within = true
    output do |str|
      str << c.save 
      yield(str)
      str << c.restore
    end
  ensure
    @within = false
  end

  def char_set set
    @_last_set ||= []
    output do |str|
      str << @_last_set.push(set).last
      yield(str)
      str << (@_last_set.pop == c.rmacs ? c.smacs : c.rmacs) || c.rmacs
    end
  end
  private :char_set

  # Render symbols within the provided block
  def symbol arg = nil, &block
    if block and not arg
      char_set c.smacs, &block 
    elsif arg and not block
      @_last_set.last == c.rmacs ? "#{c.smacs}#{arg.to_s}#{c.rmacs}" : arg.to_s 
    else
      raise "couldn't determine current character set"
    end
  end
  alias :symbols :symbol

  def alpha arg = nil, &block
    if block and not arg
      char_set c.rmacs, &block 
    elsif arg and not block
      @_last_set.last == c.smacs ? "#{c.rmacs}#{arg.to_s}#{c.smacs}" : arg.to_s 
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
    # with a dummyvalue we can identify in the subsequent command string.
    # then, we can do simple % substitition on the memoized macro string
    #file, line = block.source_location
    #File.open(file) do |f|
    #  lines = f.each_line
    #  (line - 1).times { lines.next }
    #  macro_string = lines.next
    #  raise "no macro at location" unless ident = macro_string.match(/macro/).begin(0)
    #  loop do 
    #    line = lines.next
    #    macro_string << line 
    #    break if line.match(/end/).try(:begin,0) == ident
    #  end
    #  puts "macro---"
    #  puts macro_string 
    #end
    @cache.define_singleton_method(name, &block) 
  end
  private :fl_macro
  
  # Memoize a sequence of commands as a string. For example, moving to the last column
  # and drawing an X.  You can also create function like macros, which have the effect
  # of defining singleton methods on the self and calling them as needed.
  # TODO make the function like macros memoize to text and do string substitution on them
  # although that's going to require ripper, etc.
  # Variables defined within the scope of the macro block will be memoized
  # when the macro is created, so they probably will not work as you 
  # expect. If you need a changing value within a macro, you need specify
  # a block argument for it.  In general, if you find yourself needing 
  # to do calculations in a macro, you should define a method on
  # your object.
  # If you REALLY don't want to do that, use the "context" method
  def macro name, arr = nil, &block
    if (not block.nil? and arr) or (block.nil? and not arr)
      raise ArgumentError "Array of commands or a block required."
    end
    
    if block.arity > 0
      fl_macro name, &block
    else
      if arr
        ol_macro name, arr
      elsif not block.nil
        ol_macro name, &block
      end
    end
  end

  def context name, &block
    unless @cache.respond_to? :name
      raise "can't create context for a macro that doesn't exisit"
    end
    self.define_singleton_method(name, &block)
  end

  def window row,col, width, height, opts = {}
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
  
  def c
    @cache
  end

  def build_cache
    @cache = CommandCache.new
  end
  private :build_cache
  
  @cache = CommandCache.new

  def self.cache
    @cache
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

  undef :build_cache
   
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
