
# Shell tab completion functionality
class TabCompleter
  def initialize(command_parser)
    @command_parser = command_parser
  end

  # Parse the input line to handle backslash-escaped spaces correctly
  def parse_input_for_completion(line, cursor_pos)
    # If we have a CommandParser instance, use it
    if @command_parser
      # For completion, we need to know what part of the command we're completing

      # Use only the text up to the cursor position
      line_to_cursor = line[0...cursor_pos]

      # Use command parser's tokenize method to get tokens respecting escapes
      tokens = @command_parser.tokenize_command(line_to_cursor)

      # If we have tokens and the last character is a space, we're starting a new token
      if tokens.empty? || (line_to_cursor[-1] =~ /\s/ && line_to_cursor[-2] != "\\")
        return "", "" # Start of a new token
      else
        current_token = tokens.last || ""
        prefix = tokens.size > 1 ? tokens[0..-2].join(" ") + " " : ""
        return current_token, prefix
      end
    else
      # Fallback for when command parser isn't available
      return line, ""
    end
  end

  def generate_completions(token, line, cursor_pos)
    current_token, prefix = parse_input_for_completion(line, cursor_pos)

    # Use the current token for completion
    directory_list = Dir.glob("#{current_token}**")
    if directory_list.size > 0
      # First, add trailing slashes for directories (this is the normal behavior)
      terms = directory_list.map {
        File.directory?(_1) ? _1 + "/" : _1
      }
    else
      # No matching files or directories, try history
      terms = Reline::HISTORY.grep(/^#{Regexp.escape(current_token)}/)
    end

    # Escape spaces in completions
    terms = terms.map{_1.gsub(" ","\\ ")}
    puts
    puts terms.join("\n")
    terms
  end
end



