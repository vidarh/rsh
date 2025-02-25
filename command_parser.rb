class CommandParser
  attr_reader :loader

  def initialize(loader)
    @loader = loader
  end

  def parse_input(input)
    return { type: :empty } if input.nil? || input.strip.empty?
    
    if input[0] == ?:
      { type: :ruby, code: input[1..-1] }
    else
      parse_shell_command(input)
    end
  end

  def parse_shell_command(input)
    # Parse quoted arguments properly
    tokens = tokenize_command(input)
    cmd = tokens[0]
    args = (tokens[1..-1] || []).map { |arg| strip_quotes(arg) }

    if loader.exists?(cmd)
      { type: :custom_command, command: cmd, args: args }
    else
      { type: :system, command: input }
    end
  end
  
  def tokenize_command(input)
    tokens = []
    current_token = ""
    in_double_quotes = false
    in_single_quotes = false
    escaped = false
    
    i = 0
    while i < input.length
      char = input[i]
      
      if escaped
        # If previous character was a backslash, add current character regardless
        current_token << char
        escaped = false
      elsif char == "\\"
        # Start of escape sequence, don't add the backslash
        escaped = true
      elsif char == '"' && !in_single_quotes
        in_double_quotes = !in_double_quotes
        current_token << char
      elsif char == "'" && !in_double_quotes
        in_single_quotes = !in_single_quotes
        current_token << char
      elsif char =~ /\s/ && !in_double_quotes && !in_single_quotes
        tokens << current_token unless current_token.empty?
        current_token = ""
      else
        current_token << char
      end
      
      i += 1
    end
    
    tokens << current_token unless current_token.empty?
    tokens
  end
  
  def strip_quotes(arg)
    # Strip matching quotes from the beginning and end of a string
    if (arg.start_with?('"') && arg.end_with?('"')) || 
       (arg.start_with?("'") && arg.end_with?("'"))
      arg[1..-2]
    else
      arg
    end
  end
end