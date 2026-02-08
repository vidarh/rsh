# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build/Test Commands
- Run all tests: `ruby test/run_tests.rb`
- Run single test: `ruby -Itest test/test_file.rb`
- Reload shell: `reload` (from within running shell)

## Code Style
- Use Ruby shorthand syntax when appropriate (`def method = ...`)
- Command pattern for shell functionality with each command in commands/ directory
- Error handling via specific exception rescue blocks with colorized backtrace
- File organization: commands in commands/, tests in test/, core shell in rsh.rb
- Test with Minitest (follow existing test patterns)
- Tokenization/parsing in command_parser.rb
- Keep command implementations small and focused
- Follow existing naming conventions (snake_case)
- Prefer single quotes for strings without interpolation
- Prefer Ruby-like syntax over shell-specific features

## Shell Architecture
- Commands must implement `call` method
- Commands are dynamically loaded via Loader class
- TabCompleter handles completion logic
- CommandParser handles tokenization and argument processing