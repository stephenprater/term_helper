module TermHelper
  module Widgets
    class Window < Widget
      def draw row, col, width, height, opts = {}
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
    end
  end
end
