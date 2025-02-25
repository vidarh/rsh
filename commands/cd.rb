def call(dir = nil, ...)
  pwd = Dir.pwd
  dir = ENV["OLDPWD"] if dir == "-"
  Dir.chdir(dir || ENV["HOME"])
  ENV["OLDPWD"] = pwd
  nil
end