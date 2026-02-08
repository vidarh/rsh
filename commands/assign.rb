require 'toml-rb'
require 'fileutils'
# ColorCodes module is already available in the shell

def save_assigns(assigns)
  Assigns.instance.save(assigns)
end

def load_assigns
  Assigns.list
end

def call(arg1 = nil, arg2 = nil, ...)
  # Handle 'assign list' command
  if arg1 == 'list'
    assigns = load_assigns
    if assigns.empty?
      puts colorize("No assigns defined", :yellow)
    else
      puts colorize("Current assigns:", :bold) + colorize("", :underline)
      
      # Calculate padding based on longest assign name
      max_name_width = assigns.keys.map(&:length).max + 1 # +1 for the colon
      
      assigns.each do |name, path|
        name_formatted = colorize("#{name}:", :cyan).ljust(max_name_width + 10) # Add padding for color codes
        
        # For paths with assign references, show both the reference and resolved path
        if path.include?(':')
          begin
            resolved_path = Assigns.instance.resolve_path(path)
            path_formatted = colorize(path, :yellow)
            resolved_formatted = colorize(" → #{resolved_path}", :green)
            puts "#{name_formatted} #{path_formatted}#{resolved_formatted}"
          rescue StandardError => e
            path_formatted = colorize(path, :yellow)
            error_formatted = colorize(" → Error: #{e.message}", :red)
            puts "#{name_formatted} #{path_formatted}#{error_formatted}"
          end
        else
          path_formatted = colorize(path, :green)
          puts "#{name_formatted} #{path_formatted}"
        end
      end
    end
    return
  end
  
  # Handle 'assign <name>: <dir>' command
  if arg1 && arg1.end_with?(":") && arg2
    name = arg1.chomp(":")
    
    # Handle 'assign <name>: remove' command
    if arg2 == "remove"
      assigns = load_assigns
      if assigns.key?(name)
        assigns.delete(name)
        save_assigns(assigns)
        puts colorize("Removed assign #{name}:", :green)
      else
        puts colorize("Error: Assign #{name}: does not exist", :red)
      end
      return
    end
    
    # Handle regular assign creation/update
    # For paths with assign references, store them as-is
    if arg2.include?(':')
      assign_name = arg2.split(':', 2)[0]
      
      # Verify the assign exists
      assigns = load_assigns
      unless assigns.key?(assign_name)
        puts colorize("Error: Referenced assign '#{assign_name}:' does not exist", :red)
        return
      end
      
      # Check if this would create a circular reference
      begin
        resolved_path = Assigns.instance.resolve_path(arg2)
      rescue StandardError => e
        puts colorize("Error: #{e.message}", :red)
        return
      end
      
      # Verify the resolved path exists
      unless Dir.exist?(resolved_path)
        puts colorize("Error: Resolved directory '#{resolved_path}' does not exist", :red)
        return
      end
      
      # Store the original path with the assign reference
      assigns[name] = arg2
      save_assigns(assigns)
      puts colorize("Assigned ", :green) + 
           colorize("#{name}:", :cyan) + 
           colorize(" => ", :green) + 
           colorize(arg2, :yellow) + 
           colorize(" (resolves to ", :green) + 
           colorize(resolved_path, :blue) + 
           colorize(")", :green)
    else
      # For regular paths, expand and verify as before
      path = File.expand_path(arg2)
      
      unless Dir.exist?(path)
        puts colorize("Error: Directory '#{path}' does not exist", :red)
        return
      end
      
      assigns = load_assigns
      assigns[name] = path
      save_assigns(assigns)
      puts colorize("Assigned ", :green) + 
           colorize("#{name}:", :cyan) + 
           colorize(" => ", :green) + 
           colorize(path, :blue)
    end
    return
  end
  
  # Show help message for invalid syntax
  puts colorize("Usage:", :bold)
  puts colorize("  assign <name>: <directory>", :cyan) + " - Create/update assign"
  puts colorize("  assign <name>: remove", :cyan) + " - Remove assign"
  puts colorize("  assign list", :cyan) + " - List all assigns"
end