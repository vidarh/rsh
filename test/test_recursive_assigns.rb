require 'minitest/autorun'
require 'fileutils'
require 'toml-rb'
require_relative '../assigns'

class TestRecursiveAssigns < Minitest::Test
  def setup
    # Set up a test environment
    @test_dir = File.expand_path('~/test_recursive_assigns')
    @test_config_dir = File.join(@test_dir, '.config/rterm')
    @test_assigns_file = File.join(@test_config_dir, 'assigns.toml')
    
    # Clean up any existing test environment
    FileUtils.rm_rf(@test_dir) if File.exist?(@test_dir)
    
    # Create test directories
    FileUtils.mkdir_p(@test_config_dir)
    FileUtils.mkdir_p(File.join(@test_dir, 'desktop'))
    FileUtils.mkdir_p(File.join(@test_dir, 'desktop/projects'))
    FileUtils.mkdir_p(File.join(@test_dir, 'desktop/projects/ruby'))
    
    # Set up test environment
    @old_home = ENV['HOME']
    ENV['HOME'] = @test_dir
    
    # Reset Assigns instance to ensure clean state
    @assigns = Assigns.instance
    @assigns.instance_variable_set(:@assigns, {})
    @assigns.instance_variable_set(:@assigns_mtime, 0)
    
    # Create test assigns
    assigns = {
      'home' => @test_dir,
      'desktop' => File.join(@test_dir, 'desktop'),
      'projects' => 'desktop:projects'
    }
    
    # Save the test assigns
    FileUtils.mkdir_p(@test_config_dir)
    File.open(@test_assigns_file, 'w') do |file|
      file.write(TomlRB.dump(assigns))
    end
  end
  
  def teardown
    # Clean up test environment
    ENV['HOME'] = @old_home
    FileUtils.rm_rf(@test_dir) if File.exist?(@test_dir)
  end
  
  def test_basic_assign_resolution
    # Test a direct assign
    assert_equal File.join(@test_dir, 'desktop'), Assigns['desktop']
  end
  
  def test_recursive_assign_resolution
    # Test a recursive assign
    expected_path = File.join(@test_dir, 'desktop/projects')
    assert_equal expected_path, Assigns['projects']
  end
  
  def test_multi_level_assign_resolution
    # Add a deeper level of recursion
    assigns = Assigns.list
    assigns['ruby'] = 'projects:ruby'
    @assigns.save(assigns)
    
    # Test resolution through multiple levels
    expected_path = File.join(@test_dir, 'desktop/projects/ruby')
    assert_equal expected_path, Assigns['ruby']
  end
  
  def test_circular_reference_detection
    # Create a circular reference
    assigns = Assigns.list
    assigns['circular1'] = 'circular2:'
    assigns['circular2'] = 'circular1:'
    @assigns.save(assigns)
    
    # Attempting to resolve should raise an error
    assert_raises RuntimeError do
      Assigns['circular1']
    end
  end
  
  def test_resolve_path_with_additional_components
    # Force load the assigns to make sure everything is up to date
    @assigns.load
    
    # Test resolving a path that includes an assign plus additional path components
    # First check the base path resolves correctly
    base_path = @assigns.resolve_path('projects:')
    assert_equal File.join(@test_dir, 'desktop/projects'), base_path, 
      "Basic assign resolution failed: got #{base_path.inspect}"
    
    # Now check with additional path
    path = 'projects:ruby/lib'
    expected_path = File.join(@test_dir, 'desktop/projects/ruby/lib')
    resolved_path = @assigns.resolve_path(path)
    assert_equal expected_path, resolved_path, 
      "Path resolution with additional components failed: got #{resolved_path.inspect}, expected #{expected_path.inspect}"
  end
  
  def test_assign_update_cascades
    # Test that changing a base assign updates paths that reference it
    original_projects_path = Assigns['projects']
    
    # Create a new desktop location
    new_desktop = File.join(@test_dir, 'new_desktop')
    FileUtils.mkdir_p(File.join(new_desktop, 'projects'))
    
    # Update the desktop assign
    assigns = Assigns.list
    assigns['desktop'] = new_desktop
    @assigns.save(assigns)
    
    # The projects path should now refer to the new location
    new_projects_path = Assigns['projects']
    assert_equal File.join(new_desktop, 'projects'), new_projects_path
    refute_equal original_projects_path, new_projects_path
  end
end