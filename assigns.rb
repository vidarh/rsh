require 'toml-rb'
require 'fileutils'

class Assigns
  def initialize
    @assigns = {}
    @assigns_mtime = 0
  end

  def load
    assigns_file = File.expand_path('~/.config/rterm/assigns.toml')
    
    if File.exist?(assigns_file)
      current_mtime = File.mtime(assigns_file).to_i
      if @assigns_mtime != current_mtime
          @assigns = TomlRB.load_file(assigns_file)
        @assigns_mtime = current_mtime
      end
    else
      @assigns = {}
    end
    
    @assigns
  rescue Exception => e
    p e
    @assigns = {}
  end

  def save(assigns)
    assigns_file = File.expand_path('~/.config/rterm/assigns.toml')
    assigns_dir = File.dirname(assigns_file)
    
    # Ensure directory exists
    FileUtils.mkdir_p(assigns_dir) unless Dir.exist?(assigns_dir)
    
    # Write to file
    File.open(assigns_file, 'w') do |file|
      file.write(TomlRB.dump(assigns))
    end
    
    # Update cache
    @assigns = assigns
    @assigns_mtime = File.mtime(assigns_file).to_i
  end

  def [](assign_name)
    load
    resolve_path(@assigns[assign_name])
  end
  
  # Resolve a path that may contain assign references
  def resolve_path(path, max_depth = 10)
    return path if path.nil? || !path.include?(':')
    
    depth = 0
    current_path = path
    
    while current_path.include?(':') && depth < max_depth
      # Find the first assign reference in the path
      parts = current_path.split(':', 2)
      assign_name = parts[0].downcase
      additional_path = parts[1]
      
      # Check if the assign exists
      if @assigns.key?(assign_name)
        # Replace the assign reference with its value
        base_path = @assigns[assign_name]
        
        # If the base path also contains assigns, resolve it first (recursive)
        if base_path.include?(':')
          next_depth = depth + 1
          if next_depth >= max_depth
            raise "Maximum recursion depth reached resolving assign: #{path}. Possible circular reference."
          end
          base_path = resolve_path(base_path, max_depth - next_depth)
        end
        
        # Join with any additional path components
        current_path = additional_path.empty? ? base_path : File.join(base_path, additional_path)
      else
        # If assign doesn't exist, return the original path
        return path
      end
      
      depth += 1
    end
    
    # If we reached the maximum recursion depth, return an error indicator
    if depth >= max_depth
      raise "Maximum recursion depth reached resolving assign: #{path}. Possible circular reference."
    end
    
    current_path
  end

  def []=(name, path)
    assigns = load
    assigns[name] = path
    save(assigns)
  end

  def exists?(assign_name)
    load
    @assigns.key?(assign_name)
  end

  def list
    load
  end

  def format_path(path)
    assigns = load
    return path if assigns.empty?

    # Sort assigns by path length (descending) to match the longest path first
    sorted_assigns = assigns.sort_by { |_, p| 
      # For assigns that reference other assigns, use the resolved path length
      resolved_p = resolve_path(p) rescue p
      -resolved_p.to_s.length 
    }
    
    sorted_assigns.each do |name, assign_path|
      # Resolve the assign path to handle nested assigns
      resolved_assign_path = resolve_path(assign_path) rescue assign_path
      
      if path.start_with?(resolved_assign_path)
        # Replace the path prefix with the assign name
        relative_path = path[resolved_assign_path.length..-1]
        # Remove leading slash for clean display
        relative_path = relative_path[1..-1] if relative_path.start_with?('/')
        return "#{name}:#{relative_path}"
      end
    end
    
    # If no assign matches, return the original path
    path
  end

  # Class methods that operate on the singleton instance
  def self.instance
    @instance ||= new
  end
  
  def self.[](assign_name)
    instance[assign_name]
  end
  
  def self.[]=(name, path)
    instance[name] = path
  end
  
  def self.exists?(assign_name)
    instance.exists?(assign_name)
  end
  
  def self.list
    instance.list
  end
  
  def self.format_path(path)
    instance.format_path(path)
  end
end
