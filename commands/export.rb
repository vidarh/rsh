# ColorCodes module is already available in the shell

def call(*args)
  args = args.join(" ")
  
  # Handle 'export' with no arguments - show current environment
  if args.empty?
    puts colorize("Current environment variables:", :bold) + colorize("", :underline)
    ENV.sort.each do |key, value|
      key_formatted = colorize(key, :cyan)
      value_formatted = colorize(value, :green)
      puts "#{key_formatted}=#{value_formatted}"
    end
    return
  end
  
  # Handle 'export VAR=value' syntax
  if args.include?('=')
    key, value = args.split('=', 2)
    key = key.strip
    
    # Remove quotes if present
    if (value.start_with?('"') && value.end_with?('"')) || 
       (value.start_with?("'") && value.end_with?("'"))
      value = value[1...-1]
    end
    
    # Handle variable expansion (e.g., $PATH)
    if value.include?('$')
      # Match $VAR or ${VAR} patterns
      value = value.gsub(/\$([A-Za-z0-9_]+)|\$\{([A-Za-z0-9_]+)\}/) do |match|
        var_name = $1 || $2
        ENV[var_name] || ''
      end
    end
    
    # Set the environment variable
    ENV[key] = value
    puts colorize("Set environment variable: ", :green) + 
         colorize(key, :cyan) + 
         colorize("=", :green) + 
         colorize(value, :yellow)
    return
  end
  
  # Show help message for invalid syntax
  puts colorize("Usage:", :bold)
  puts colorize("  export", :cyan) + " - List all environment variables"
  puts colorize("  export VAR=value", :cyan) + " - Set environment variable"
  puts colorize("  export VAR=\"quoted value\"", :cyan) + " - Set with quoted value (preserves spaces)"
  puts colorize("  export PATH=$PATH:/new/path", :cyan) + " - Append to existing variable"
end