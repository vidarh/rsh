require 'minitest/autorun'
require 'timeout'
require 'pty'

# Comprehensive smoke test suite for rsh.
# Guards against regressions that previous signal-handling fix attempts introduced:
# - Shell startup crashes
# - Shell dying after first command
# - Interactive programs getting SIGTTIN (background process group without tcsetpgrp)
# - Broken implicit cd
# - Broken builtins
# - Broken Ruby evaluation
# - Terminal access failures
#
# These tests MUST ALL PASS before any signal-handling changes are applied.
# If ANY test fails after a change, that change must be reverted immediately.

class TestShellSmoke < Minitest::Test
  RSH_PATH = File.expand_path('../../rsh.rb', __FILE__)
  TIMEOUT_SECONDS = 5

  # Pipe-based tests for basic command execution
  def run_shell_commands(commands)
    stdin_r, stdin_w = IO.pipe
    stdout_r, stdout_w = IO.pipe
    stderr_r, stderr_w = IO.pipe

    input_script = (commands + ["exit"]).join("\n")

    pid = Process.spawn(
      "ruby", RSH_PATH,
      in: stdin_r,
      out: stdout_w,
      err: stderr_w,
      pgroup: true
    )

    stdin_r.close
    stdout_w.close
    stderr_w.close

    begin
      Timeout.timeout(TIMEOUT_SECONDS) do
        stdin_w.write(input_script)
        stdin_w.close

        Process.wait(pid)
        status = $?

        output = stdout_r.read
        stderr_output = ""
        begin
          stderr_output = stderr_r.read_nonblock(4096)
        rescue IO::WaitReadable, EOFError
          # No stderr output
        end

        return {
          output: output,
          exit_status: status,
          stderr: stderr_output
        }
      end
    rescue Timeout::Error
      Process.kill('TERM', -pid) rescue nil
      Process.wait(pid) rescue nil
      flunk("Shell hung or became unresponsive during test")
    ensure
      [stdin_w, stdout_r, stderr_r].each { |io| io.close rescue nil }
    end
  end

  # PTY-based test helper for interactive operations
  def run_pty_test(timeout: 5)
    output_buffer = +''

    Timeout.timeout(timeout) do
      PTY.spawn(RbConfig.ruby, RSH_PATH) do |rsh_out, rsh_in, shell_pid|
        rsh_out.sync = true
        rsh_in.sync = true

        # Wait for initial prompt
        sleep 0.3

        # Let the test block interact with the shell
        yield rsh_out, rsh_in, output_buffer

        # Clean up
        Process.kill('TERM', shell_pid) rescue nil
      end
    end
  rescue Timeout::Error
    flunk "PTY test timed out - shell hung"
  end

  def read_with_timeout(io, timeout)
    buffer = +''
    deadline = Time.now + timeout

    loop do
      remaining = deadline - Time.now
      break if remaining <= 0

      ready = IO.select([io], nil, nil, remaining)
      break unless ready

      begin
        buffer << io.read_nonblock(4096)
      rescue IO::WaitReadable
        next
      rescue EOFError, Errno::EIO
        break
      end
    end

    buffer
  end

  # === PIPE-BASED TESTS (for basic execution) ===

  def test_shell_survives_single_command
    result = run_shell_commands(["echo hello"])

    assert result[:exit_status].success?,
      "Shell should exit cleanly, got status #{result[:exit_status].exitstatus}"

    assert_match(/hello/, result[:output],
      "Shell should execute echo command and output 'hello'")
  end

  def test_shell_survives_multiple_sequential_commands
    commands = [
      "echo first",
      "echo second",
      "echo third"
    ]

    result = run_shell_commands(commands)

    assert result[:exit_status].success?,
      "Shell should survive multiple commands, got status #{result[:exit_status].exitstatus}"

    assert_match(/first/, result[:output], "Should see output from first command")
    assert_match(/second/, result[:output], "Should see output from second command")
    assert_match(/third/, result[:output], "Should see output from third command")
  end

  def test_shell_handles_command_with_arguments
    result = run_shell_commands(["echo hello world"])

    assert result[:exit_status].success?,
      "Shell should handle commands with arguments"

    assert_match(/hello world/, result[:output],
      "Shell should pass arguments correctly")
  end

  def test_shell_survives_five_commands
    commands = 5.times.map { |i| "echo command_#{i}" }

    result = run_shell_commands(commands)

    assert result[:exit_status].success?,
      "Shell should survive 5 sequential commands"

    commands.each_with_index do |cmd, i|
      assert_match(/command_#{i}/, result[:output],
        "Should see output from command #{i}")
    end
  end

  def test_shell_handles_builtin_pwd
    result = run_shell_commands(["pwd"])

    assert result[:exit_status].success?,
      "Shell should handle pwd builtin"

    # pwd should output a path
    assert_match(/\//, result[:output],
      "pwd should output a path")
  end

  def test_shell_survives_nonexistent_command
    result = run_shell_commands(["this_command_does_not_exist_12345"])

    assert result[:exit_status].success?,
      "Shell should survive executing a nonexistent command"

    # Should see error message but shell shouldn't crash
    assert_match(/No such (command|file or directory)|command not found/i, result[:output] + result[:stderr],
      "Should show error message for nonexistent command")
  end

  # === PTY-BASED TESTS (for interactive features) ===

  def test_interactive_stdin_with_cat
    # CRITICAL: This test catches the SIGTTIN regression from process groups
    # without tcsetpgrp. If this fails, interactive programs are broken.
    got_echo = false
    output_debug = ''

    run_pty_test do |rsh_out, rsh_in, buffer|
      # Wait for shell to be ready
      read_with_timeout(rsh_out, 1)

      # Run cat - it should read from STDIN and echo
      rsh_in.write("cat\n")
      sleep 0.5  # Give cat time to start

      # Send input
      rsh_in.write("test line from cat\n")
      sleep 0.5  # Give cat time to echo

      # Read ALL accumulated output
      output = read_with_timeout(rsh_out, 1)
      output_debug = output
      got_echo = output.include?("test line from cat")

      # Send EOF to terminate cat
      rsh_in.write("\x04")  # Ctrl-D
      sleep 0.3
    end

    assert got_echo, "cat should be able to read from STDIN. Got: #{output_debug.inspect}"
  end

  def test_interactive_stdin_with_ruby_gets
    # Another SIGTTIN guard - ruby programs reading STDIN
    got_output = false
    output_debug = ''

    run_pty_test do |rsh_out, rsh_in, buffer|
      read_with_timeout(rsh_out, 1)

      # Start a Ruby program that reads from STDIN
      rsh_in.write("ruby -e 'STDOUT.sync=true; line=gets; puts \"GOT:\#{line}\"'\n")
      sleep 0.5  # Give ruby time to start and block on gets

      # Send input
      rsh_in.write("test input\n")
      sleep 0.5  # Give ruby time to output

      # Read ALL accumulated output
      output = read_with_timeout(rsh_out, 1)
      output_debug = output
      got_output = output.include?("GOT:test input")
    end

    assert got_output, "ruby gets should work. Got: #{output_debug.inspect}"
  end

  def test_terminal_access_with_io_console
    # CRITICAL: Guards against SIGTTOU when children try terminal operations
    # This was a failure mode in previous fix attempts
    got_winsize = false
    output_debug = ''

    run_pty_test do |rsh_out, rsh_in, buffer|
      read_with_timeout(rsh_out, 1)

      # Run a program that accesses the terminal
      rsh_in.write("ruby -e 'require \"io/console\"; puts IO.console.winsize.inspect'\n")
      sleep 0.5

      output = read_with_timeout(rsh_out, 1)
      output_debug = output
      got_winsize = output.match?(/\[\d+,\s*\d+\]/)
    end

    assert got_winsize, "IO.console should work. Got: #{output_debug.inspect}"
  end

  def test_implicit_cd
    # The current system() method handles exit codes 127/126 by trying implicit cd
    # This feature MUST be preserved
    changed_dir = false
    output_debug = ''

    run_pty_test do |rsh_out, rsh_in, buffer|
      read_with_timeout(rsh_out, 1)

      # Type a directory name directly (implicit cd)
      rsh_in.write("/tmp\n")
      sleep 0.3

      # Check current directory with pwd
      rsh_in.write("pwd\n")
      sleep 0.3

      output = read_with_timeout(rsh_out, 1)
      output_debug = output
      changed_dir = output.include?("/tmp")
    end

    assert changed_dir, "Implicit cd should work. Got: #{output_debug.inspect}"
  end

  def test_builtin_cd
    # Builtins must continue to work
    changed_dir = false
    output_debug = ''

    run_pty_test do |rsh_out, rsh_in, buffer|
      read_with_timeout(rsh_out, 1)

      # Use explicit cd command
      rsh_in.write("cd /tmp\n")
      sleep 0.3

      # Check with pwd
      rsh_in.write("pwd\n")
      sleep 0.3

      output = read_with_timeout(rsh_out, 1)
      output_debug = output
      changed_dir = output.include?("/tmp")
    end

    assert changed_dir, "cd builtin should work. Got: #{output_debug.inspect}"
  end

  def test_ruby_evaluation
    # The shell supports Ruby evaluation with ':' prefix
    got_result = false
    output_debug = ''

    run_pty_test do |rsh_out, rsh_in, buffer|
      read_with_timeout(rsh_out, 1)

      # Evaluate Ruby code
      rsh_in.write(":puts 1+1\n")
      sleep 0.3

      output = read_with_timeout(rsh_out, 1)
      output_debug = output
      got_result = output.include?("2")
    end

    assert got_result, "Ruby evaluation should work. Got: #{output_debug.inspect}"
  end

  def test_shell_startup_reaches_prompt
    # Shell must start successfully without crashing
    started = false
    output_debug = ''

    run_pty_test do |rsh_out, rsh_in, buffer|
      # If we can read anything and send a command, shell started
      output = read_with_timeout(rsh_out, 2)

      # Try a simple command to verify shell is responsive
      rsh_in.write("echo test\n")
      sleep 0.3

      output = read_with_timeout(rsh_out, 1)
      output_debug = output
      started = output.include?("test")
    end

    assert started, "Shell should start and be responsive. Got: #{output_debug.inspect}"
  end
end
