require 'test/unit'
require 'reline'
require_relative '../command_parser'
require_relative '../loader'
require_relative '../tabcompleter'

class TestTabCompleter < Test::Unit::TestCase
  def setup
    @loader = Loader.new(File.join(File.dirname(__FILE__), "..", "commands"))
    @loader.load_commands
    @command_parser = CommandParser.new(@loader)
    @tab_completer = TabCompleter.new(@command_parser)

    # Create temporary test directories
    @test_dir = File.join(File.dirname(__FILE__), "tmp_test_dir")
    @subdir = File.join(@test_dir, "subdir")

    FileUtils.rm_rf(@test_dir) if File.exist?(@test_dir)
    FileUtils.mkdir_p(@subdir)

    # Create some files for testing
    FileUtils.touch(File.join(@test_dir, "file1.txt"))
    FileUtils.touch(File.join(@test_dir, "file2.txt"))
    FileUtils.touch(File.join(@subdir, "subfile.txt"))
  end

  def teardown
    FileUtils.rm_rf(@test_dir) if File.exist?(@test_dir)
  end

  def complete(line)
    @tab_completer.generate_completions(nil, line, line.length)
  end

  def test_basic_completion
    completions = complete("cd #{@test_dir}/file")
    assert_equal(2, completions.size)
    assert completions.include?("#{@test_dir}/file1.txt")
    assert completions.include?("#{@test_dir}/file2.txt")
  end

  def test_directory_completion_with_trailing_slash
    completions = complete("cd #{@test_dir}/")

    assert completions.include?("#{@test_dir}/subdir/"),
      "Directory completions should include trailing slash: #{completions.inspect}"
    assert completions.include?("#{@test_dir}/file1.txt")
    assert completions.include?("#{@test_dir}/file2.txt")

    completions = complete("cd #{@test_dir}/subdir/")

    assert !completions.empty?,
      "Should be able to complete contents inside directory with trailing slash"
    assert completions.include?("#{@test_dir}/subdir/subfile.txt"),
      "Should include files inside the directory: #{completions.inspect}"
  end

  def test_completion_with_empty_directory_and_trailing_slash
    Dir.chdir(@test_dir) do
      empty_dir = "empty_dir"
      FileUtils.mkdir_p(empty_dir)

      completions = @tab_completer.generate_completions(nil, "cd #{empty_dir}/", "cd #{empty_dir}/".length)

      assert_equal([], completions)
    end
  end

  def test_parse_input_for_completion_with_trailing_slash
    current_token, prefix = @tab_completer.parse_input_for_completion("cd #{@test_dir}/", "cd #{@test_dir}/".length)

    assert_equal("#{@test_dir}/", current_token)
    assert_equal("cd ", prefix)

    line = "cd Desktop/"
    cursor_pos = line.length

    current_token, prefix = @tab_completer.parse_input_for_completion(line, cursor_pos)

    assert_equal("Desktop/", current_token,
      "Current token should be 'Desktop/' including the trailing slash")
    assert_equal("cd ", prefix,
      "Prefix should be 'cd ' (with a space)")
  end

  def test_glob_pattern_with_trailing_slash
    pattern_with_slash = "#{@test_dir}/*/"
    matches = Dir.glob(pattern_with_slash)
    assert_equal(1, matches.size)
    assert_equal("#{@test_dir}/subdir/", matches[0])

    pattern_without_slash = "#{@test_dir}/*"
    matches = Dir.glob(pattern_without_slash)
    assert_equal(3, matches.size)

    pattern_with_dir_and_slash = "#{@test_dir}/subdir/*"
    matches = Dir.glob(pattern_with_dir_and_slash)
    assert_equal(1, matches.size)
    assert_equal("#{@test_dir}/subdir/subfile.txt", matches[0])
  end
end
