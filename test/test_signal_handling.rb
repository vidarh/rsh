require 'minitest/autorun'
require 'timeout'
require 'pty'
require 'tmpdir'

class TestSignalHandling < Minitest::Test
  READY_MARKER = '__CHILD_READY__'
  INT_MARKER = '__CHILD_GOT_INT__'
  ECHO_PREFIX = '__CHILD_ECHO__'
  SHELL_MARKER = '__SHELL_ALIVE__'

  def setup
    @rsh_path = File.expand_path('../../rsh.rb', __FILE__)
    @pidfile = File.join(Dir.tmpdir, "rsh-test-#{Process.pid}-#{rand(10000)}.pid")
  end

  def teardown
    File.delete(@pidfile) if File.exist?(@pidfile)
  end

  def test_ctrl_c_terminates_child_process
    # This test demonstrates the expected behavior:
    # When Ctrl-C is sent while a command is running:
    # 1. The child process should receive SIGINT
    # 2. The child process should terminate
    # 3. The shell should NOT terminate
    # 4. The shell should be ready for the next command

    child_pid = nil
    shell_alive = false
    child_received_int = false
    child_terminated = false

    # Ruby command that traps SIGINT and reports it
    test_cmd = build_test_command(@pidfile, READY_MARKER, INT_MARKER, ECHO_PREFIX)

    Timeout.timeout(8) do
      PTY.spawn(RbConfig.ruby, @rsh_path) do |rsh_out, rsh_in, shell_pid|
        rsh_out.sync = true
        rsh_in.sync = true

        # Wait for shell to be ready
        read_with_timeout(rsh_out, 2)

        # Start the test command
        rsh_in.write("#{test_cmd}\n")

        # Wait for child to be ready and record its PID
        output = read_until_marker(rsh_out, READY_MARKER, 2)
        child_pid = wait_for_pidfile(@pidfile, 2)

        # Send SIGINT to the child's process group (which should be the foreground group)
        # The fix makes each child its own process group and gives it foreground control
        if child_pid
          child_pgrp = Process.getpgid(child_pid.to_i) rescue child_pid.to_i
          Process.kill('INT', -child_pgrp)  # Negative PID sends to process group
        end
        sleep 0.2

        # Check if child received SIGINT
        output = read_with_timeout(rsh_out, 1)
        child_received_int = output.include?(INT_MARKER)

        # Give a bit more time for the child to fully exit and be reaped
        sleep 0.3

        # Check if child terminated
        if child_pid
          child_terminated = !process_alive?(child_pid.to_i)
        end

        # Try to interact with the shell
        rsh_in.write(":puts \"#{SHELL_MARKER}\"\n")
        output = read_until_marker(rsh_out, SHELL_MARKER, 2)
        shell_alive = output.include?(SHELL_MARKER)

        # Clean up
        Process.kill('TERM', shell_pid) rescue nil
        if child_pid && process_alive?(child_pid.to_i)
          Process.kill('TERM', child_pid.to_i) rescue nil
        end
      end
    end

    # These assertions describe what SHOULD happen
    assert child_received_int, "Child process should receive SIGINT when Ctrl-C is pressed"
    assert child_terminated, "Child process should terminate after receiving SIGINT"
    assert shell_alive, "Shell should remain responsive after Ctrl-C terminates child"
  rescue Timeout::Error
    flunk "Test timed out - likely the shell hung after Ctrl-C (demonstrates the bug)"
  end

  def test_ctrl_c_does_not_affect_subsequent_commands
    # This test verifies that after Ctrl-C terminates a command,
    # the shell can still execute subsequent commands normally

    test_cmd = build_test_command(@pidfile, READY_MARKER, INT_MARKER, ECHO_PREFIX)
    got_test123 = false

    Timeout.timeout(8) do
      PTY.spawn(RbConfig.ruby, @rsh_path) do |rsh_out, rsh_in, shell_pid|
        rsh_out.sync = true
        rsh_in.sync = true

        # Wait for shell
        read_with_timeout(rsh_out, 2)

        # Start command and interrupt it
        rsh_in.write("#{test_cmd}\n")
        read_until_marker(rsh_out, READY_MARKER, 2)
        child_pid = wait_for_pidfile(@pidfile, 2)
        if child_pid
          child_pgrp = Process.getpgid(child_pid.to_i) rescue child_pid.to_i
          Process.kill('INT', -child_pgrp)
        end
        read_with_timeout(rsh_out, 1)

        # Try to run another command
        rsh_in.write("echo test123\n")
        output = read_with_timeout(rsh_out, 2)
        got_test123 = output.include?('test123')

        # Clean up
        Process.kill('TERM', shell_pid) rescue nil
      end
    end

    # The shell should be able to execute the echo command
    assert got_test123, "Shell should execute subsequent commands after Ctrl-C"
  rescue Timeout::Error
    flunk "Test timed out - shell hung after Ctrl-C (demonstrates the bug)"
  end

  def test_rapid_ctrl_c_presses
    # This test checks that multiple rapid Ctrl-C presses don't cause issues:
    # - No zombie processes
    # - No orphaned process groups
    # - Shell remains responsive

    test_cmd = build_test_command(@pidfile, READY_MARKER, INT_MARKER, ECHO_PREFIX)
    child_alive = nil
    shell_alive = false

    Timeout.timeout(8) do
      PTY.spawn(RbConfig.ruby, @rsh_path) do |rsh_out, rsh_in, shell_pid|
        rsh_out.sync = true
        rsh_in.sync = true

        read_with_timeout(rsh_out, 2)

        # Start command
        rsh_in.write("#{test_cmd}\n")
        read_until_marker(rsh_out, READY_MARKER, 2)
        child_pid = wait_for_pidfile(@pidfile, 2)

        # Send multiple rapid SIGINT to child process group
        if child_pid
          child_pgrp = Process.getpgid(child_pid.to_i) rescue child_pid.to_i
          3.times do
            Process.kill('INT', -child_pgrp) rescue Errno::ESRCH
            sleep 0.05
          end
        end

        sleep 0.3

        # Verify child is dead
        child_alive = child_pid && process_alive?(child_pid.to_i)

        # Verify shell is responsive
        rsh_in.write(":puts \"#{SHELL_MARKER}\"\n")
        output = read_until_marker(rsh_out, SHELL_MARKER, 2)
        shell_alive = output.include?(SHELL_MARKER)

        # Clean up
        Process.kill('TERM', shell_pid) rescue nil
        if child_alive
          Process.kill('TERM', child_pid.to_i) rescue nil
        end
      end
    end

    assert !child_alive, "Child should be terminated after rapid Ctrl-C presses"
    assert shell_alive, "Shell should remain responsive after rapid Ctrl-C"
  rescue Timeout::Error
    flunk "Test timed out - shell hung after rapid Ctrl-C (demonstrates the bug)"
  end

  def test_child_that_traps_sigint
    # This test verifies that if a child process has its own SIGINT handler,
    # it receives the signal and can handle it as it chooses

    # Command that traps SIGINT but doesn't exit immediately
    custom_trap_cmd = build_custom_trap_command(@pidfile, READY_MARKER, INT_MARKER)
    child_got_signal = false

    Timeout.timeout(8) do
      PTY.spawn(RbConfig.ruby, @rsh_path) do |rsh_out, rsh_in, shell_pid|
        rsh_out.sync = true
        rsh_in.sync = true

        read_with_timeout(rsh_out, 2)

        rsh_in.write("#{custom_trap_cmd}\n")
        read_until_marker(rsh_out, READY_MARKER, 2)
        child_pid = wait_for_pidfile(@pidfile, 2)

        # Send SIGINT to child process group
        if child_pid
          child_pgrp = Process.getpgid(child_pid.to_i) rescue child_pid.to_i
          Process.kill('INT', -child_pgrp)
        end

        # Check if child printed its custom handler message
        output = read_with_timeout(rsh_out, 2)
        child_got_signal = output.include?(INT_MARKER)

        Process.kill('TERM', shell_pid) rescue nil
      end
    end

    # Child's custom handler should have run
    assert child_got_signal, "Child's custom SIGINT handler should execute"
  rescue Timeout::Error
    flunk "Test timed out - shell hung (demonstrates the bug)"
  end

  def test_interactive_child_can_read_stdin_with_ruby_gets
    # CRITICAL TEST: This verifies that interactive programs can access STDIN.
    # This is the test that would have caught the process group regression.
    # When a child is put in a background process group without tcsetpgrp,
    # it cannot read from the terminal and gets SIGTTIN.

    input_text = "test input line"
    got_output = false
    output_buffer = +''

    Timeout.timeout(8) do
      PTY.spawn(RbConfig.ruby, @rsh_path) do |rsh_out, rsh_in, shell_pid|
        rsh_out.sync = true
        rsh_in.sync = true

        # Wait for shell prompt
        read_with_timeout(rsh_out, 2)

        # Start a Ruby program that reads from STDIN
        rsh_in.write("ruby -e 'STDOUT.sync=true; line=gets; puts \"GOT:\#{line}\"'\n")
        sleep 0.3  # Give the child time to start and block on gets

        # Send input to the child
        rsh_in.write("#{input_text}\n")

        # Read output - should see the echoed line
        output = read_with_timeout(rsh_out, 2)
        output_buffer = output
        got_output = output.include?("GOT:#{input_text}")

        # Clean up
        Process.kill('TERM', shell_pid) rescue nil
      end
    end

    assert got_output, "Interactive child should be able to read from STDIN. Got: #{output_buffer.inspect}"
  rescue Timeout::Error
    flunk "Test timed out - child likely blocked trying to read STDIN (SIGTTIN)"
  end

  def test_interactive_child_can_read_stdin_with_cat
    # Another critical STDIN test using the common 'cat' command.
    # cat reads from STDIN and echoes to STDOUT - a fundamental interactive program.

    input_text = "hello from cat"
    got_echo = false

    Timeout.timeout(8) do
      PTY.spawn(RbConfig.ruby, @rsh_path) do |rsh_out, rsh_in, shell_pid|
        rsh_out.sync = true
        rsh_in.sync = true

        read_with_timeout(rsh_out, 2)

        # Run cat - it should read from STDIN and echo
        rsh_in.write("cat\n")
        sleep 0.3

        # Send input
        rsh_in.write("#{input_text}\n")

        # Should see echo
        output = read_with_timeout(rsh_out, 2)
        got_echo = output.include?(input_text)

        # Send EOF to terminate cat
        rsh_in.write("\x04")  # Ctrl-D
        sleep 0.2

        Process.kill('TERM', shell_pid) rescue nil
      end
    end

    assert got_echo, "cat should be able to read from STDIN and echo output"
  rescue Timeout::Error
    flunk "Test timed out - cat likely blocked trying to read STDIN"
  end

  def test_program_can_access_terminal_for_console_operations
    # This test verifies that programs needing terminal control can access it.
    # Programs using IO.console or terminal ioctl operations need foreground
    # process group control. Without tcsetpgrp, they get SIGTTOU.

    got_winsize = false

    Timeout.timeout(8) do
      PTY.spawn(RbConfig.ruby, @rsh_path) do |rsh_out, rsh_in, shell_pid|
        rsh_out.sync = true
        rsh_in.sync = true

        read_with_timeout(rsh_out, 2)

        # Run a program that accesses the terminal
        rsh_in.write("ruby -e 'require \"io/console\"; puts IO.console.winsize.inspect'\n")

        # Should see output like "[24, 80]" (rows, cols)
        output = read_with_timeout(rsh_out, 2)
        got_winsize = output.match?(/\[\d+,\s*\d+\]/)

        Process.kill('TERM', shell_pid) rescue nil
      end
    end

    assert got_winsize, "Programs should be able to access terminal for console operations"
  rescue Timeout::Error
    flunk "Test timed out - program likely received SIGTTOU trying to access terminal"
  end

  private

  def build_test_command(pidfile, ready_marker, int_marker, echo_prefix)
    ruby_code = [
      'STDOUT.sync = true',
      'STDERR.sync = true',
      "path = \"#{pidfile}\"",  # Use double quotes to avoid quote nesting issues
      'File.write(path, Process.pid.to_s)',
      "puts \"#{ready_marker}\"",
      "trap(\"INT\") { puts \"#{int_marker}\"; exit 130 }",
      'while (line = STDIN.gets)',
      "  print \"#{echo_prefix}\"",
      '  print line',
      'end'
    ].join('; ')

    "ruby -e '#{ruby_code}'"
  end

  def build_custom_trap_command(pidfile, ready_marker, int_marker)
    ruby_code = [
      'STDOUT.sync = true',
      "path = \"#{pidfile}\"",  # Use double quotes to avoid quote nesting issues
      'File.write(path, Process.pid.to_s)',
      "puts \"#{ready_marker}\"",
      "trap(\"INT\") { puts \"#{int_marker}\"; sleep 0.5 }",
      'sleep 10'
    ].join('; ')

    "ruby -e '#{ruby_code}'"
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

  def read_until_marker(io, marker, timeout)
    buffer = +''
    deadline = Time.now + timeout

    loop do
      remaining = deadline - Time.now
      break if remaining <= 0

      ready = IO.select([io], nil, nil, remaining)
      break unless ready

      begin
        buffer << io.read_nonblock(4096)
        return buffer if buffer.include?(marker)
      rescue IO::WaitReadable
        next
      rescue EOFError, Errno::EIO
        break
      end
    end

    buffer
  end

  def wait_for_pidfile(path, timeout)
    deadline = Time.now + timeout
    loop do
      return File.read(path).strip if File.exist?(path)
      break if Time.now >= deadline
      sleep 0.05
    end
    nil
  end

  def process_alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  end
end
