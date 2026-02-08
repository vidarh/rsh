require 'reline'
require_relative 'loader'
require_relative 'command_parser'
require_relative 'assigns'
require_relative 'prompt'
require_relative 'utils/color_codes'

begin
  require 'rouge'
  require 'rouge/gtk_theme_loader'

  $rouge_theme = Rouge::Theme.find("plasticcodewrap").new # rescue nil
  $rouge_lexer = Rouge::Lexer.find("sh")
  $rouge_ruby = Rouge::Lexer.find("ruby")
  $rouge_formatter = Rouge::Formatters::Terminal256.new($rouge_theme)
rescue Exception => e
  p e
  puts e.backtrace.join(" ")
end

def format(str, lexer: $rouge_lexer)
  $rouge_formatter.format(lexer.lex(str))
end

def smart_format(input)
  if input[0] == ?:
    ":" + format(input[1..-1], lexer: $rouge_ruby)
  else
    format(input, lexer: $rouge_lexer)
  end
end

def autocolorize(str) = str.gsub(/^(.*?):(\d+):(in\s+.*)/, "\e[36m\\1\e[0m:\e[33m\\2\e[0m:\e[31m\\3\e[0m")

require_relative 'tabcompleter'

# Reline completion proc
comp = proc do |s, line, cursor_pos|
  $tab_completer.generate_completions(s, line, cursor_pos)
end

#rd, wr = IO.pipe
#if !fork
#  while ch = rd.getc
#    $stderr.print(ch.inspect+" ")
#  end
#end

#Readline.output = wr
# Note: Requires Reline 0.2.8+ for line_buffer and point methods
Reline.completion_append_character = ""
Reline.completion_proc = proc do |s|
  # Use the new completion with line buffer and cursor position
  comp.call(s, Reline.line_buffer, Reline.point)
end
Reline.completer_quote_characters = %{'"}
Reline.output_modifier_proc = proc do |input, complete:|
  smart_format(input)
end

class CtrlC < StandardError
end

trap("SIGINT") {
  puts "^C"
  raise CtrlC
}

require 'fiddle'

# TIOCSPGRP ioctl constant - set foreground process group
# 0x5410 is the value on Linux
TIOCSPGRP = 0x5410

def tcsetpgrp(fd, pgrp)
  libc = Fiddle.dlopen(nil)
  ioctl = Fiddle::Function.new(
    libc['ioctl'],
    [Fiddle::TYPE_INT, Fiddle::TYPE_LONG, Fiddle::TYPE_VOIDP],
    Fiddle::TYPE_INT
  )

  pgrp_ptr = Fiddle::Pointer.malloc(Fiddle::SIZEOF_INT)
  pgrp_ptr[0, Fiddle::SIZEOF_INT] = [pgrp].pack('i')

  result = ioctl.call(fd, TIOCSPGRP, pgrp_ptr)
  raise SystemCallError.new("tcsetpgrp", Fiddle.last_error) if result == -1
  result
end

def system(command)
  # Check if we're running in a terminal (needed for tcsetpgrp)
  is_tty = STDIN.tty?

  # Save original signal handlers
  old_int = trap("INT", "IGNORE")
  old_ttou = trap("TTOU", "IGNORE") if is_tty

  # Get shell's process group for restoration later
  shell_pgrp = Process.getpgrp if is_tty

  pid = fork do
    # In child: put ourselves in our own process group (if in a terminal)
    Process.setpgid(0, 0) if is_tty

    # Restore default signal handlers in child
    trap("INT", "DEFAULT")
    trap("TTOU", "DEFAULT") if is_tty

    begin
      exec(command)
    rescue Errno::ENOENT
      # Use exit code 127 to indicate command not found
      exit(127)
    rescue Errno::EACCES
      # Use exit code 126 to indicate permission denied
      exit(126)
    rescue Exception => e
      present_exception(e)
    end
    exit(0)
  end

  if pid
    begin
      if is_tty
        # In parent: put child in its own process group
        Process.setpgid(pid, pid)

        # Give terminal foreground control to child's process group
        tcsetpgrp(STDIN.fileno, pid)
      end

      # Wait for child to complete
      Process.wait(pid)
      status = $?.exitstatus
    ensure
      if is_tty
        # Restore terminal foreground control to shell
        begin
          tcsetpgrp(STDIN.fileno, shell_pgrp)
        rescue => e
          # If tcsetpgrp fails (e.g., child already exited), continue anyway
        end

        # Restore original signal handlers
        trap("TTOU", old_ttou)
      end

      trap("INT", old_int)
    end

    # Handle different error cases
    case status
    when 127, 126 # Command not found or permission denied
      # Try implicit cd with the first token of the command
      tokens = $command_parser.tokenize_command(command)
      path = tokens[0]

      # Only try implicit cd if there's only one token (just a path, no args)
      if tokens.size == 1
        begin
          $loader.call('cd', path)
          # If cd succeeds, don't show "No such command"
          return
        rescue
          # If cd fails, show the appropriate error
          if status == 127
            puts "No such command"
          else
            puts "Permission denied - #{path}"
          end
        end
      else
        # Show the appropriate error for commands with arguments
        if status == 127
          puts "No such command"
        else
          puts "Permission denied - #{command}"
        end
      end
    end
  end
end

# FIXME: This breaks things like re,
# so perhaps colorizing this way isn't a good general solution.
# Might do it in the terminal instead.
def system2(command)
  IO.popen(command) do |f|
    f.each_line do |l|
      l.gsub!(/([\u2500-\u25ff`|+\-]+)/,"\e[32m\\1\e[39m")
      l.gsub!(/([\{\}]+)/,"\e[33m\\1\e[39m")
      print l
    end
  end
rescue Errno::ENOENT
  puts "No such command"
rescue Exception => e
  present_exception(e)
end


def present_exception(e)
  puts format(e.inspect, lexer: $rouge_ruby)
  puts e.backtrace.map{autocolorize(_1)}.join("\n")
end

# Builtin commands moved to commands/ directory

def handle_command(input)
  result = $command_parser.parse_input(input)
  
  case result[:type]
  when :empty
    return
  when :custom_command
    $last = r = $loader.call(result[:command], *result[:args])
    if r
      puts(format(r.inspect, lexer: $rouge_ruby))
    end
  when :system
    $last = system(result[:command])
  end
end

def run(*args)

  # FIXME: Handle more.
  if args[0]
    handle_command(args[0].join)
  end
  
  while input = Reline.readline(prompt, true)
    puts "\033[A\r#{prompt}#{smart_format(input)}\033[K\033[J"
    
    Reline::HISTORY.pop if input == ""

    result = $command_parser.parse_input(input)
    
    case result[:type]
    when :ruby
      begin
        r = eval(result[:code])
        puts format(r.inspect, lexer: $rouge_ruby) if r
      rescue Exception => e
        puts format(e.inspect, lexer: $rouge_ruby)
      end
    else
      handle_command(input)
    end
  end
rescue CtrlC
  retry
rescue Exception => e
  present_exception(e)
  retry
end

$loader = Loader.new(File.join(File.dirname(__FILE__),"commands"))
$loader.load_commands
$command_parser = CommandParser.new($loader)
$tab_completer = TabCompleter.new($command_parser)

def reload
  $norun=true
  load(__FILE__)
end

run(ARGV[1..-1]) unless $norun
