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
    args = tokens[1..-1] || []

    if loader.exists?(cmd)
      { type: :custom_command, command: cmd, args: args }
    elsif respond_to?("builtin_#{cmd}", true)
      { type: :builtin, command: cmd, args: args }
    else
      { type: :system, command: input }
    end
  end
  
  def tokenize_command(input)
    tokens = []
    current_token = ""
    in_double_quotes = false
    in_single_quotes = false
    
    input.chars.each do |char|
      if char == '"' && !in_single_quotes
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
    end
    
    tokens << current_token unless current_token.empty?
    tokens
  end
end