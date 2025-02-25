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

  def test_parse_command_cd
    @loader.expect :exists?, true, ["cd"]
    result = @parser.parse_input("cd /home")
    assert_equal :custom_command, result[:type]
    assert_equal "cd", result[:command]
    assert_equal ["/home"], result[:args]
    @loader.verify
  end
  
  def test_parse_command_pwd
    @loader.expect :exists?, true, ["pwd"]
    result = @parser.parse_input("pwd")
    assert_equal :custom_command, result[:type]
    assert_equal "pwd", result[:command]
    assert_equal [], result[:args]
    @loader.verify
  end
  
  def test_parse_command_hist
    @loader.expect :exists?, true, ["hist"]
    result = @parser.parse_input("hist")
    assert_equal :custom_command, result[:type]
    assert_equal "hist", result[:command]
    assert_equal [], result[:args]
    @loader.verify
  end
  
  def test_parse_command_exit
    @loader.expect :exists?, true, ["exit"]
    result = @parser.parse_input("exit")
    assert_equal :custom_command, result[:type]
    assert_equal "exit", result[:command]
    assert_equal [], result[:args]
    @loader.verify
  end
  
  def test_parse_command_pstree
    @loader.expect :exists?, true, ["pstree"]
    result = @parser.parse_input("pstree -a")
    assert_equal :custom_command, result[:type]
    assert_equal "pstree", result[:command]
    assert_equal ["-a"], result[:args]
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
    assert_equal ["hello world", "single quoted"], result[:args]
    @loader.verify
  end
  
  def test_parse_escaped_quotes
    @loader.expect :exists?, true, ["echo"]
    result = @parser.parse_input("echo \"escaped \\\"quote\\\"\" 'nested \\'quote\\''")
    assert_equal :custom_command, result[:type]
    assert_equal "echo", result[:command]
    assert_equal ["escaped \\\"quote\\\"", "nested \\'quote\\'"], result[:args]
    @loader.verify
  end
  
  def test_parse_empty_quoted_strings
    @loader.expect :exists?, true, ["echo"]
    result = @parser.parse_input("echo \"\" '' ")
    assert_equal :custom_command, result[:type]
    assert_equal "echo", result[:command]
    assert_equal ["", ""], result[:args]
    @loader.verify
  end
  
  def test_strip_quotes
    assert_equal "hello world", @parser.strip_quotes("\"hello world\"")
    assert_equal "single quoted", @parser.strip_quotes("'single quoted'")
    assert_equal "no quotes", @parser.strip_quotes("no quotes")
    assert_equal "mismatched\"", @parser.strip_quotes("mismatched\"")
    assert_equal "mismatched'", @parser.strip_quotes("mismatched'")
    assert_equal "", @parser.strip_quotes("\"\"")
    assert_equal "", @parser.strip_quotes("''")
  end
end