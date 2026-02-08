require 'minitest/autorun'
require 'fileutils'
require 'toml-rb'
require_relative '../assigns'
require_relative '../utils/color_codes'
require_relative '../loader'

class TestAssigns < Minitest::Test
  def setup
    # Set up a test environment
    @test_dir = File.expand_path('~/test_assigns')
    @test_config_dir = File.join(@test_dir, '.config/rterm')
    @test_assigns_file = File.join(@test_config_dir, 'assigns.toml')
    
    # Clean up any existing test environment
    FileUtils.rm_rf(@test_dir) if File.exist?(@test_dir)
    
    # Create test directories
    FileUtils.mkdir_p(@test_config_dir)
    FileUtils.mkdir_p(File.join(@test_dir, 'target_dir'))
    FileUtils.mkdir_p(File.join(@test_dir, 'subdir/nested'))
    
    # Set up test environment
    @old_home = ENV['HOME']
    ENV['HOME'] = @test_dir
    
    # Load commands
    @loader = Loader.new(File.join(File.dirname(__FILE__), '..', 'commands'))
    @loader.load_commands
    
    # Reset Assigns instance to ensure clean state
    Assigns.instance.instance_variable_set(:@assigns, {})
    Assigns.instance.instance_variable_set(:@assigns_mtime, 0)
  end
  
  def teardown
    # Clean up test environment
    ENV['HOME'] = @old_home
    FileUtils.rm_rf(@test_dir) if File.exist?(@test_dir)
  end
  
  def test_assign_and_cd_with_assign
    # Make sure commands are loaded
    assert @loader.exists?('assign')
    assert @loader.exists?('cd')
    
    # Create an assign
    @loader.call('assign', 'test:', File.join(@test_dir, 'target_dir'))
    
    # Check if the assigns file was created
    assert File.exist?(@test_assigns_file)
    
    # Check if the assign was saved correctly
    assigns = TomlRB.load_file(@test_assigns_file)
    assert_equal File.join(@test_dir, 'target_dir'), assigns['test']
    
    # Test CD with assign
    current_dir = Dir.pwd
    @loader.call('cd', 'test:')
    assert_equal File.join(@test_dir, 'target_dir'), Dir.pwd
    
    # Change back to original directory
    Dir.chdir(current_dir)
  end
  
  def test_cd_with_assign_and_path
    # Make sure commands are loaded
    assert @loader.exists?('assign')
    assert @loader.exists?('cd')
    
    # Create an assign and a nested directory
    @loader.call('assign', 'sub:', File.join(@test_dir, 'subdir'))
    
    # Test CD with assign followed by a path
    current_dir = Dir.pwd
    @loader.call('cd', 'sub:nested')
    assert_equal File.join(@test_dir, 'subdir/nested'), Dir.pwd
    
    # Change back to original directory
    Dir.chdir(current_dir)
  end
  
  def test_assign_list
    # Create some test assigns
    assigns = {
      'test1' => File.join(@test_dir, 'target_dir'),
      'test2' => @test_dir
    }
    
    # Save the test assigns
    FileUtils.mkdir_p(@test_config_dir)
    File.open(@test_assigns_file, 'w') do |file|
      file.write(TomlRB.dump(assigns))
    end
    
    # Test the list command
    assert_output(/Current assigns:.*test1:.*test2:/m) do
      @loader.call('assign', 'list')
    end
  end
  
  def test_assign_remove
    # Create some test assigns
    assigns = {
      'test1' => File.join(@test_dir, 'target_dir'),
      'test2' => @test_dir
    }
    
    # Save the test assigns
    FileUtils.mkdir_p(@test_config_dir)
    File.open(@test_assigns_file, 'w') do |file|
      file.write(TomlRB.dump(assigns))
    end
    
    # Test the remove command
    assert_output(/Removed assign test1:/) do
      @loader.call('assign', 'test1:', 'remove')
    end
    
    # Verify assign was removed
    assigns = TomlRB.load_file(@test_assigns_file)
    refute_includes assigns.keys, 'test1', "Assign 'test1' should have been removed"
    assert_includes assigns.keys, 'test2', "Assign 'test2' should still exist"
    
    # Test removing non-existent assign
    assert_output(/Error: Assign nonexistent: does not exist/) do
      @loader.call('assign', 'nonexistent:', 'remove')
    end
  end
  
  def test_path_expansion
    current_dir = Dir.pwd
    
    # Change to the test directory
    Dir.chdir(@test_dir)
    
    # Test with relative path (.)
    @loader.call('assign', 'dot:', '.')
    
    # Test with relative path (..)
    @loader.call('assign', 'dotdot:', '../test_assigns')
    
    # Test with tilde
    @loader.call('assign', 'home:', '~')
    
    # Test with nested relative path
    Dir.chdir(File.join(@test_dir, 'subdir'))
    @loader.call('assign', 'nested:', './nested')
    
    # Load assigns and verify they were expanded properly
    assigns = TomlRB.load_file(@test_assigns_file)
    
    # Check expansions
    assert_equal @test_dir, assigns['dot'], "The '.' path should be expanded to the full path"
    assert_equal @test_dir, assigns['dotdot'], "The '..' path should be expanded to the full path"
    assert_equal @test_dir, assigns['home'], "The '~' path should be expanded to the HOME path"
    assert_equal File.join(@test_dir, 'subdir/nested'), assigns['nested'], "The './nested' path should be expanded correctly"
    
    # Change back to original directory
    Dir.chdir(current_dir)
  end
end