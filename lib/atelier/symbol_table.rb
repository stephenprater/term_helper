module Atelier
  class SymbolTable
    class << self
      TABLE = {
        right_arrow:            '+',
        left_arrow:             ',',
        up_arrow:               '-',
        down_arrow:             '.',
        square:                 '0',
        diamond:                '`',
        shade:                  'a',
        degree:                 'f',
        plus_minus:             'g',
        shade2:                 'h',
        apple:                  'i',
        ll:                     'j',
        ul:                     'k',
        ur:                     'l',
        lr:                     'm',
        inter:                  'n',
        h_line_top:             'o',
        h_line_three_quarter:   'p',
        h_line:                 'q',
        h_line_one_quarter:     'r',
        h_line_bottom:          's',
        left_inter:             't',
        right_inter:            'u',
        up_inter:               'v',
        down_inter:             'w',
        v_line:                 'x',
        lessthan_equal:         'y',
        greaterthan_equal:      'z',
        pi:                     '{',
        approx:                 '|',
        pound:                  '}',
        dot:                    '~'
      }

      def symbol_lookup meth
        TABLE.has_key? meth ? TABLE[meth] : nil
      end
    end
  end
end
