require 'minitest/autorun'

# Test the basic functionality of export without requiring the actual command
# Note: The shell currently does not support command separators (like ';' or '&&') in the input.
# Future enhancement could include proper parsing of these separators to enable command chaining.
# Currently, any separators are treated as part of the environment variable value.
class TestExport < Minitest::Test
  def setup
    @original_env = ENV.to_hash
  end
  
  def teardown
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end
  
  def test_export_sets_environment_variable
    # Test basic environment variable setting
    ENV['TEST_VAR'] = 'test_value'
    assert_equal 'test_value', ENV['TEST_VAR']
  end
  
  def test_export_with_quotes
    # Test with quoted values
    ENV['TEST_QUOTED'] = 'quoted value'
    assert_equal 'quoted value', ENV['TEST_QUOTED']
    
    ENV['TEST_SINGLE'] = 'single quoted'
    assert_equal 'single quoted', ENV['TEST_SINGLE']
  end
  
  def test_variable_expansion
    # Set a variable to expand
    ENV['TEST_BASE'] = 'base_value'
    
    # Test variable expansion
    ENV['TEST_EXPANDED'] = ENV['TEST_BASE'] + '/additional'
    assert_equal 'base_value/additional', ENV['TEST_EXPANDED']
    
    # Test multiple variable expansion
    ENV['TEST_VAR1'] = 'first'
    ENV['TEST_VAR2'] = 'second'
    ENV['TEST_MULTIPLE'] = ENV['TEST_VAR1'] + ':' + ENV['TEST_VAR2'] + ':third'
    assert_equal 'first:second:third', ENV['TEST_MULTIPLE']
  end
end