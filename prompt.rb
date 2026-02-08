require_relative 'assigns'
require_relative 'utils'

def prompt
  @last_pwd ||= nil
  @formatted_pwd ||= nil
  
  pwd = Dir.pwd
  
  if @last_pwd != pwd
    # First format the path with assign
    formatted_pwd = Assigns.format_path(pwd)
    
    # Then replace home with tilde for display
    home = ENV["HOME"]
    formatted_pwd.gsub!(/\A#{home}/,"~") if formatted_pwd.start_with?(home)
    
    @last_pwd = pwd
    @formatted_pwd = formatted_pwd
  end
  
  # Create segments array based on path
  if @formatted_pwd.include?(":")
    prefix, rest = @formatted_pwd.split(":", 2)
    segments = [:prefix, "#{prefix}:"]
    segments.concat([:path, rest]) if !rest.empty?
  else
    segments = [:path, @formatted_pwd]
  end
  
  output_semantic_segments(segments)
end
