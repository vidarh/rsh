def output_semantic_segments(segments)
  return "" if segments.empty?
  
  # Add default empty segment at the end to handle the final transition
  segments = segments.dup
  segments << :default << ""
  
  # Store color codes directly without escape sequences
  colors = {
    prefix:  { fg: 37, bg: 42 },  # White on green
    path:    { fg: 37, bg: 44 },  # White on blue
    default: { fg: 37, bg: 40 }   # Default terminal colors (black bg)
  }
  
  separator = "\uE0B0"
  path_separator = " \uE0B1 "
  result = ""
  
  segments.each_slice(2).each_with_index do |(type, content), index|
    # Get current segment colors
    current = colors[type] || colors[:default]

    if type == :path
      content = content.gsub("/", path_separator)
    end
    
    # Add current segment with its own colors
    result << "\e[#{current[:bg]}m\e[#{current[:fg]}m #{content}"
    
    # Handle transition to next segment if there is one
    if index < segments.each_slice(2).count - 1
      next_type = segments[index * 2 + 2]
      next_colors = colors[next_type] || colors[:default]
      
      # Separator: 
      # - foreground color = current bg color (using standard foreground escape sequence)
      # - background color = next bg color
      result << "\e[#{next_colors[:bg]}m\e[3#{current[:bg] % 10}m#{separator}"
    end
  end
  
  # Reset all colors at the end
  result << "\e[0m"
  
  result
end
