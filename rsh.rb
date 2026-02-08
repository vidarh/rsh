require 'reline'
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

def system(command)
  pid = fork do
    begin
      exec(command)
    rescue Errno::ENOENT
      puts "No such command"
    rescue Exception => e
      present_exception(e)
    end
    exit(0)
  end
  Process.wait(pid) if pid
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
