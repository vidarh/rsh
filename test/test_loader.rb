require 'minitest/autorun'
require 'fileutils'
require 'tempfile'
require_relative '../loader'

class TestLoader < Minitest::Test
  def setup
    @temp_dir = Dir.mktmpdir
    @loader = Loader.new(@temp_dir)
  end

  def teardown
    FileUtils.remove_entry @temp_dir
  end

  def test_initialize
    assert_equal @temp_dir, @loader.instance_variable_get(:@command_dir)
    assert_equal({}, @loader.instance_variable_get(:@commands))
  end

  def test_exists
    assert_equal false, @loader.exists?("test_command")
    
    # Create a mock command file
    File.write(File.join(@temp_dir, "test_command.rb"), "def call(*args); 'test'; end")
    @loader.load_command("test_command")
    
    assert_equal true, @loader.exists?("test_command")
  end

  def test_load_command_with_valid_command
    # Create a mock command file
    File.write(File.join(@temp_dir, "test_command.rb"), "def call(*args); 'test_output'; end")
    @loader.load_command("test_command")
    
    assert @loader.exists?("test_command")
    assert_equal "test_output", @loader.call("test_command")
  end

  def test_load_command_with_invalid_command
    # Create a mock command file without call method
    File.write(File.join(@temp_dir, "invalid_command.rb"), "def execute(*args); 'test'; end")
    
    # Capture stdout to test error message
    output = capture_io { @loader.load_command("invalid_command") }
    
    assert_equal false, @loader.exists?("invalid_command")
    assert_match(/Error: invalid_command does not implement 'call' method/, output[0])
  end

  def test_load_command_with_syntax_error
    # Create a mock command file with syntax error
    File.write(File.join(@temp_dir, "syntax_error.rb"), "def call(*args); 'test' end}")
    
    # Capture stdout to test error message
    output = capture_io { @loader.load_command("syntax_error") }
    
    assert_equal false, @loader.exists?("syntax_error")
    assert_match(/Error loading syntax_error:/, output[0])
  end

  def test_load_commands
    # Create mock command files
    File.write(File.join(@temp_dir, "cmd1.rb"), "def call(*args); 'cmd1_output'; end")
    File.write(File.join(@temp_dir, "cmd2.rb"), "def call(*args); 'cmd2_output'; end")
    
    @loader.load_commands
    
    assert @loader.exists?("cmd1")
    assert @loader.exists?("cmd2")
    assert_equal "cmd1_output", @loader.call("cmd1")
    assert_equal "cmd2_output", @loader.call("cmd2")
  end
end