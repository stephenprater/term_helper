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
      black: 1,
      green: 2,
      gray: 3,
      lime: 4,
      silver: 5,
      olive: 6,
      white: 7,
      yellow: 8,
      red: 9,
      navy: 10,
      maroon: 11,
      blue: 12,
      purple: 13,
      teal: 14,
      fuchsia: 15,
      aqua: 16
    }

      
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
        c = b.is_a?(Proc) ? b : lambda { b }
        define_method meth, &c
      end
    end
  end
  
  attr_reader :cache

  # abstractions around common escape sequences or construction
  def output string = nil 
    to_stdout = true if string
    string = "" unless string.respond_to? :<<
    yield(string) if block_given? # modifiy str in place
    if to_stdout 
      $stdout << string
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
  
  def remove_tempfile(path)
    proc { system "rm #{path}"; } 
  end
  module_function :remove_tempfile

  def color color
    output do |str|
      str << c.setaf(color)
      str << yield(str)
      str << c.reset
    end
  end

  def size
    {:rows => `tput lines`.chomp, :cols => `tput cols`.chomp}
  end

  def there_and_back
    raise "nested there_and_back" if @within
    @within = true
    string = output do |str|
      str << c.save 
      yield(str)
      str << c.restore
    end
    string
  ensure
    @within = false
  end

  def symbols 
    output do |str|
      str << c.smacs 
      str << yield(str)
      str << c.rmacs 
    end
  end

  def symbol arg
    "#{c.smacs}#{arg}#{c.rmacs}"
  end

  def macro name, arr = nil
    string = ""
    if (block_given? and arr) or (not block_given? and not arr)
      raise ArgumentError "Array of commands or a block required."
    elsif block_given?
      str = ""
      string = yield str
    elsif arr
      string = arr.inject "" do |c| 
        self.__send__ *c
      end
    end
    @cache.define_singleton_method(name) { string }
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
