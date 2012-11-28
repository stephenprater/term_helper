require 'ruby-terminfo'

module TermHelper
  class CommandCache
    COLOR_LIST = {
      black:          0,
      red:            1,
      green:          2,
      yellow:         3,
      blue:           4,
      magenta:        5,
      cyan:           6,
      white:          7,
      gray:           8,
      bold_red:       9,
      bold_green:     10,
      bold_yellow:    11,
      bold_blue:      12,
      bold_magenta:   13,
      bold_cyan:      14,
      bold_white:     15
    }

    METHOD_CAPABILITIES = {
      clear_all:        'clear',
      save:             'sc',
      restore:          'rc',
      reset:            'sgr0',
      smacs:            'smacs',
      symbol:           'smacs',
      rmacs:            'rmacs',
      alpha:            'rmacs',
      left:             'cub1',
      right:            'cuf1',
      up:               'cuu1',
      down:             'cud1',
      clear_lines:      'el',
      clear_screen:     'ed',
      clear_backward:   'el1'
      column:           'hpa',
      row:              'vpa',
      address:          'cup',
      home:             'home',
    }

    def initialize owner
      @term = TermInfo.default_object
      @owner = owner
    end

    def term
      @term
    end

    def method_missing method, *args, &block
      if owner.respond_to? method
        owner.send metho, *args, &block
      elsif METHOD_CAPABILITIES.has_key? meth
        if args.length == 0
          @term.tigetstr meth
        else
          @term.tiparm(self.tigetstr(meth), *args)
        end
      else
        super
      end
    end

    def setaf color
      color = color.is_a? Fixnum && color < 255 ? color : COLOR_LIST[color.intern]
      str = ""
      if color < 8
        str = "3#{color}"
      elsif color < 16
        str = "9#{color-8}"
      else
        str = "38;5;#{color}"
      end
      term.tiparm(term.tigetstr('setaf'),str)
    end
    alias :foreground :setaf

    def setab color
      color = color.is_a? Fixnum && color < 255 ? color : COLOR_LIST[color.intern]
      str = ""
      if color < 8
        str = "4#{color}"
      elsif color < 16
        str = "10#{color}"
      else 
        str = "48;5;#{color}"
      end
      setab % str
    end
    alias :background :setab

    def mrcup row,col
      hdir = col > 0 ? :right : :left
      vdir = row > 0 ? :down : :up 
      [[vdir,row],[hdir,col]].inject '' do |memo, dir|
        memo << ( __send__(dir[0]) * dir[1].abs)
      end
    end
    alias :move_relative :mrcup
    
    # pass it either a [row,col] array or a row:x, col:x opts hash
    def moveto *args
      row,col = *({ :row => nil, :col => nil}.merge(args.first).values rescue args)
      cmd = (col and row) ? :cup : (col ? :hpa : (row ? :vpa : :home))
      __send__(cmd, [row, col].compact)
    end
  end
end
