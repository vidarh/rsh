module ColorCodes
  RESET     = "\033[0m"
  BOLD      = "\033[1m"
  UNDERLINE = "\033[4m"
  CYAN      = "\033[36m"
  GREEN     = "\033[32m"
  YELLOW    = "\033[33m"
  RED       = "\033[31m"
  BLUE      = "\033[34m"
  MAGENTA   = "\033[35m"
end

# Helper function to colorize text
# Supports both direct color codes and symbol references (:green, :bold, etc.)
def colorize(text, color)
  color_code = if color.is_a?(Symbol)
    ColorCodes.const_get(color.to_s.upcase)
  else
    color
  end
  
  "#{color_code}#{text}#{ColorCodes::RESET}"
end