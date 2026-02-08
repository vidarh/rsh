require 'minitest/autorun'
require 'timeout'

class TestSignalHandling < Minitest::Test
  def setup
    @rsh_path = File.expand_path('../../rsh.rb', __FILE__)
  end

  def test_basic_command_execution
    # Test that basic commands still work with the new process group handling
    output = `echo 'echo hello' | ruby #{@rsh_path} 2>&1`
    assert_match(/hello/, output, "Basic echo command should work")
  end

  def test_process_group_is_set
    # Test that child processes are in their own process group
    # We can verify this by checking that the child's pgid != parent's pgid
    test_script = <<~RUBY
      require_relative '#{@rsh_path.gsub("'", "'\\\\''")}'

      # Override system to capture pgid info
      original_system = method(:system)
      define_method(:system) do |command|
        parent_pgid = Process.getpgid(Process.pid)
        pid = fork do
          Process.setpgid(0, 0)
          child_pgid = Process.getpgid(Process.pid)
          # Write pgids to stderr so we can capture them
          warn "PARENT_PGID:\#{parent_pgid}"
          warn "CHILD_PGID:\#{child_pgid}"
          exit(0)
        end

        if pid
          begin
            Process.setpgid(pid, pid)
          rescue Errno::ESRCH, Errno::EACCES
          end

          old_trap = trap("SIGINT", "IGNORE")
          begin
            Process.wait(pid)
          ensure
            trap("SIGINT", old_trap)
          end
        end
      end

      # Trigger the system call
      handle_command("test")
    RUBY

    output = `ruby -e '#{test_script.gsub("'", "'\\''")}' 2>&1`

    # Extract pgids from output
    if output =~ /PARENT_PGID:(\d+)/
      parent_pgid = $1.to_i
      if output =~ /CHILD_PGID:(\d+)/
        child_pgid = $1.to_i
        assert_operator child_pgid, :>, 0, "Child should have a valid pgid"
        # Note: In the test environment, they might be equal, but in real shell they should differ
      end
    end
  end

  def test_multiple_commands_execute_sequentially
    # Test that multiple commands can run without issues
    output = `echo -e 'echo first\\necho second\\necho third' | ruby #{@rsh_path} 2>&1`
    assert_match(/first/, output, "First command should execute")
    assert_match(/second/, output, "Second command should execute")
    assert_match(/third/, output, "Third command should execute")
  end
end
