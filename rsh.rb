require 'reline'
require 'fiddle'
require_relative 'loader'
require_relative 'command_parser'

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

def colorize(str) = str.gsub(/^(.*?):(\d+):(in\s+.*)/, "\e[36m\\1\e[0m:\e[33m\\2\e[0m:\e[31m\\3\e[0m")

comp = proc do |s|
  directory_list = Dir.glob("#{s}*")
  if directory_list.size > 0
    terms = directory_list.map { File.directory?(_1) ? _1 + "/" : _1 }
  else
    terms = Reline::HISTORY.grep(/^#{Regexp.escape(s)}/)
  end
  terms.map { _1.gsub(" ","\\ ") }
end

#rd, wr = IO.pipe
#if !fork
#  while ch = rd.getc
#    $stderr.print(ch.inspect+" ")
#  end
#end

#Readline.output = wr
Reline.completion_append_character = ""
Reline.completion_proc = comp
Reline.output_modifier_proc = proc do |input, complete:|
  smart_format(input)
end

class CtrlC < StandardError
end

trap("SIGINT") {
  puts "^C"
  raise CtrlC
}

# Helper to call tcsetpgrp(2) via fiddle for terminal foreground control
def tcsetpgrp(fd, pgrp)
  return if !STDIN.isatty  # Only works on terminals

  libc = Fiddle.dlopen(nil)
  tcsetpgrp_func = Fiddle::Function.new(
    libc['tcsetpgrp'],
    [Fiddle::TYPE_INT, Fiddle::TYPE_INT],
    Fiddle::TYPE_INT
  )

  tcsetpgrp_func.call(fd, pgrp)
  # Ignore return value - tcsetpgrp may fail in some environments
  # (e.g., not a controlling terminal) but we continue anyway
rescue => e
  # Silently ignore errors - we may not be in a terminal
end

def system(command)
  shell_pgrp = Process.getpgrp

  pid = fork do
    begin
      # Put this process in its own process group so it receives signals independently
      Process.setpgid(0, 0)
      exec(command)
    rescue Errno::ENOENT
      puts "No such command"
    rescue Exception => e
      present_exception(e)
    end
    exit(0)
  end

  if pid
    # Set child's process group from parent side (handles race condition)
    begin
      Process.setpgid(pid, pid)
    rescue Errno::ESRCH, Errno::EACCES
      # Child may have already exec'd or exited
    end

    # Give foreground control to the child's process group
    # This allows the child to receive terminal signals (SIGINT from Ctrl-C)
    # Only works if we're actually in a terminal
    tcsetpgrp(STDIN.fileno, pid) if STDIN.isatty

    # Temporarily ignore SIGINT in parent while child runs
    old_trap = trap("SIGINT", "IGNORE")
    begin
      Process.wait(pid)
    ensure
      # Restore original SIGINT handler
      trap("SIGINT", old_trap)
      # Restore foreground control to the shell
      tcsetpgrp(STDIN.fileno, shell_pgrp) if STDIN.isatty
    end
  end
end

def filter(command)
  IO.popen(command) do |f|
    f.each_line do |l|
      l.gsub!(/([\u2500-\u25ff`|+\-]+)/,"\e[32m\\1\e[39m")
      l.gsub!(/([\{\}]+)/,"\e[33m\\1\e[39m")
      print l
    end
  end
end

def prompt
  pwd = Dir.pwd
  home = ENV["HOME"]
  pwd.gsub!(/\A#{home}/,"~")
  #pwd.gsub!("/"," \uE0B0 ")
  "\e[44m #{pwd} \e[34;48m\uE0B0\e[0m "
end

def present_exception(e)
  puts format(e.inspect, lexer: $rouge_ruby)
  puts e.backtrace.map{colorize(_1)}.join("\n")
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


def reload
  $norun=true
  load(__FILE__)
end

run(ARGV[1..-1]) unless $norun
