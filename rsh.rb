require 'readline'

comp = proc do |s|
  directory_list = Dir.glob("#{s}*")
  if directory_list.size > 0
    directory_list.map { File.directory?(_1) ? _1 + "/" : _1 }
  else
    Readline::HISTORY.grep(/^#{Regexp.escape(s)}/)
  end
end
                      
Readline.completion_append_character = ""
Readline.completion_proc = comp

class CtrlC < StandardError
end

trap("SIGINT") {
  puts "^C"
  raise CtrlC
}

def system(command) = Process.wait(fork { exec(command) })

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

def self.builtin_cd(dir = nil, ...)
  pwd = Dir.pwd
  dir = ENV["OLDPWD"] if dir == "-"
  Dir.chdir(dir || ENV["HOME"])
  ENV["OLDPWD"] = pwd
end

def self.builtin_pwd(...) = puts(Dir.pwd)
def self.builtin_hist(...) = puts Readline::HISTORY.to_a
def self.builtin_exit(...) = exit(0)
def self.builtin_pstree(*args) = filter("pstree -U"+(args.join(" ")))

def run
  while input = Readline.readline(prompt, true)
    Readline::HISTORY.pop if input == ""

    if input[0] == ?:
      begin
        r = eval(input[1..-1])
        p r if r
      rescue Exception => e
        p e
      end
    else
      words = input.split(/\s/)
      cmd = words[0]
      # FIXME: Maybe move this to a module.
      builtin = "builtin_#{cmd}".to_sym
      if self.respond_to?(builtin) then self.send(builtin, *words[1..-1])
      elsif !input.empty? then system(input)
      end
    end
  end
rescue CtrlC
  retry
rescue Exception => e
  p e
  retry
end

def reload
  $norun=true
  load(__FILE__)
end

run unless $norun
