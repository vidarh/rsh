require 'minitest/autorun'
require 'fileutils'
require_relative '../assigns'
require_relative '../utils/color_codes'
require_relative '../commands/cd'

class TestCdWithAssign < Minitest::Test
  def setup
    # Create a mock Assigns implementation for testing
    @assigns = Assigns.instance
    @assigns.instance_variable_set(:@assigns, {
      'test' => '/tmp',
      'home' => ENV['HOME']
    })
  end
  
  def test_cd_with_simple_assign
    expected_dir = nil
    Dir.stub :chdir, ->(dir) { expected_dir = dir } do
      call('test:')
    end
    
    assert_equal '/tmp', expected_dir, 'cd with assign: should change to the assign path'
  end
  
  def test_cd_with_assign_and_path
    expected_dir = nil
    Dir.stub :chdir, ->(dir) { expected_dir = dir } do
      call('test:subdir')
    end
    
    assert_equal File.join('/tmp', 'subdir'), expected_dir, 
      'cd with assign:path should join the assign path with the additional path'
  end
  
  def test_cd_with_nonexistent_assign
    # Capture puts output to verify error message
    output = StringIO.new
    $stdout = output
    
    # Call cd with nonexistent assign
    call('nonexistent:subdir')
    
    # Restore stdout
    $stdout = STDOUT
    
    assert_match(/Assign nonexistent: not found/, output.string, 
      'cd with nonexistent assign should show error message')
  end
  
  def test_cd_with_home_assign_and_nested_path
    expected_dir = nil
    Dir.stub :chdir, ->(dir) { expected_dir = dir } do
      call('home:Documents/subfolder')
    end
    
    assert_equal File.join(ENV['HOME'], 'Documents/subfolder'), expected_dir,
      'cd with home:Documents/subfolder should use the home assign and append the path'
  end
end