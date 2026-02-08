
def call(dir = nil, ...)
  pwd = Dir.pwd
  dir = ENV["OLDPWD"] if dir == "-"
  
  # Handle assigns (both ending with ":" and containing ":")
  if dir && dir.include?(":")
    begin
      # Try to resolve the path directly
      resolved_path = Assigns.instance.resolve_path(dir)
      
      # If successful, use the resolved path
      if resolved_path && resolved_path != dir
        dir = resolved_path
      else
        # Fall back to the old method for better error handling
        parts = dir.split(":", 2)
        assign_name = parts[0]
        additional_path = parts[1]
        
        if Assigns.exists?(assign_name)
          base_path = Assigns[assign_name]
          dir = additional_path.empty? ? base_path : File.join(base_path, additional_path)
        else
          puts "Assign #{assign_name}: not found"
          return
        end
      end
    rescue StandardError => e
      # Handle recursion or circular reference errors
      puts "Error resolving assign: #{e.message}"
      return
    end
  end
  
  begin
    Dir.chdir(dir || ENV["HOME"])
    ENV["OLDPWD"] = pwd
    nil
  rescue Errno::ENOENT
    puts "rsh: #{dir}: No such file or directory"
    nil
  end
end