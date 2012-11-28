= Atelier - helping you draw

Atelier is a libary for making console output from various classes which
may need to report their state in manners more complex than printed
debug statements.  It's also useful for separation of concerns when
it comes to terminal output.

You can sort of think of it as a template library for terminal outputs.

In addition to providing Rubyish access to terminfo capabilities, Atelier 
provides for making 'macros' and 'widgets'. Macros in this case can be
thought of as more like Vim macros than the Lisp varieties, while widgets
can contain more complex drawings.

== Macros ==

Atelier provides two kinds of macros.  There are "string like" macros - which
are the simplest kind and simply memoize the results of calling the block
they are defined in.

The other is "function like" macros - which are defined with blocks that take
and argument.  They too memoize the results of calling the block, but will
provide late bound variables that you can use to 
