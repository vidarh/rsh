


# Ruby Shell

(C) 2024 Vidar Hokstad

MIT Licensed.

## Dependencies

 * Ruby 2.7+
 * Reline 0.2.8+ (for advanced tab completion with backslash-escaped spaces)
 * Rouge (for syntax highlighting)

## Goals

 * Easily extensible in Ruby (try ":def self.builtin_foo = puts 'hello
   world'" and then type 'foo')
 * Allow dipping into Ruby (try ":puts 'this is ruby'" or ":binding.
   irb")
