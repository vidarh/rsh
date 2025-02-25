require 'minitest/autorun'
require_relative '../command_parser'
require_relative '../loader'

class TestCommandParser < Minitest::Test
  def setup
    @loader = Minitest::Mock.new
    @parser = CommandParser.new(@loader)
  end

  def test_parse_empty_input
    assert_equal({ type: :empty }, @parser.parse_input(""))
    assert_equal({ type: :empty }, @parser.parse_input(nil))
    assert_equal({ type: :empty }, @parser.parse_input("  "))
  end

  def test_parse_ruby_code
    assert_equal({ type: :ruby, code: "puts 'hello'" }, @parser.parse_input(":puts 'hello'"))
    assert_equal({ type: :ruby, code: "1 + 2" }, @parser.parse_input(":1 + 2"))
  end

  def test_parse_custom_command
    @loader.expect :exists?, true, ["gpt"]
    result = @parser.parse_input("gpt hello world")
    assert_equal :custom_command, result[:type]
    assert_equal "gpt", result[:command]
    assert_equal ["hello", "world"], result[:args]
    @loader.verify
  end

  def test_parse_builtin_command
    @loader.expect :exists?, false, ["cd"]
    def @parser.respond_to?(method_name, include_private = false)
      method_name.to_s == "builtin_cd" || super
    end
    
    result = @parser.parse_input("cd /home")
    assert_equal :builtin, result[:type]
    assert_equal "cd", result[:command]
    assert_equal ["/home"], result[:args]
    @loader.verify
  end

  def test_parse_system_command
    @loader.expect :exists?, false, ["ls"]
    result = @parser.parse_input("ls -la")
    assert_equal :system, result[:type]
    assert_equal "ls -la", result[:command]
    @loader.verify
  end
  
  def test_parse_quoted_arguments
    @loader.expect :exists?, true, ["echo"]
    result = @parser.parse_input("echo \"hello world\" 'single quoted'")
    assert_equal :custom_command, result[:type]
    assert_equal "echo", result[:command]
    assert_equal ["\"hello world\"", "'single quoted'"], result[:args]
    @loader.verify
  end
  
  def test_parse_escaped_quotes
    @loader.expect :exists?, true, ["echo"]
    result = @parser.parse_input("echo \"escaped \\\"quote\\\"\" 'nested \\'quote\\''")
    assert_equal :custom_command, result[:type]
    assert_equal "echo", result[:command]
    assert_equal ["\"escaped \\\"quote\\\"\"", "'nested \\'quote\\''"], result[:args]
    @loader.verify
  end
  
  def test_parse_empty_quoted_strings
    @loader.expect :exists?, true, ["echo"]
    result = @parser.parse_input("echo \"\" '' ")
    assert_equal :custom_command, result[:type]
    assert_equal "echo", result[:command]
    assert_equal ["\"\"", "''"], result[:args]
    @loader.verify
  end
end