#!/usr/bin/env ruby

require 'minitest/autorun'

# Add the test directory to the load path
$LOAD_PATH.unshift(File.dirname(__FILE__))

# Load all test files
Dir.glob(File.join(File.dirname(__FILE__), 'test_*.rb')).each do |test_file|
  require File.basename(test_file)
end