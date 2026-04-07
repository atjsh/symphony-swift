#!/usr/bin/env bash
# Wrapper for Muter's test command.
#
# Two workarounds for Muter v16 + Swift 6.2:
#
# 1. Muter's Foundation.Process calls waitUntilExit() BEFORE draining the
#    stdout pipe → pipe buffer deadlock on large output. We redirect swift
#    test stdout/stderr to a log file to keep the pipe empty.
#
# 2. swiftpm-testing-helper hangs after test completion when server/SQLite
#    tests leave lingering tasks. We set a hard kill timeout.
#
# Optional env vars:
#   MUTER_TEST_TIMEOUT — override default 240s timeout
set -euo pipefail
export PATH="/usr/bin:/usr/local/bin:/opt/homebrew/bin:$PATH"

log_dir="${PWD}/muter_logs"
mkdir -p "$log_dir"
log_file="${log_dir}/swift-test-$(date +%s).log"

timeout_secs="${MUTER_TEST_TIMEOUT:-240}"

# Run swift test with timeout; kill after timeout + grace period.
# We use perl because macOS doesn't ship GNU timeout / gtimeout.
#
# IMPORTANT: When the child is killed by a signal (not a normal exit),
# $? >> 8 is 0. We must detect signal-kills and return non-zero so that
# Muter treats crashes as test failures, not passes.
_MUTER_TIMEOUT="$timeout_secs" perl -e '
  use POSIX ":sys_wait_h";
  my $timeout = $ENV{"_MUTER_TIMEOUT"};
  my $pid = fork();
  if ($pid == 0) {
    open STDOUT, ">", $ARGV[0] or die;
    open STDERR, ">&STDOUT";
    exec("/usr/bin/swift", "test", @ARGV[1..$#ARGV]) or die "exec: $!";
  }
  my $elapsed = 0;
  while ($elapsed < $timeout) {
    my $w = waitpid($pid, WNOHANG);
    if ($w > 0) {
      # Child exited normally or by signal
      my $code = $? >> 8;
      my $sig  = $? & 127;
      exit($sig ? 128 + $sig : $code);
    }
    sleep 1; $elapsed++;
  }
  # Timeout: kill child and report failure (exit 124, like GNU timeout)
  kill "TERM", $pid; sleep 2;
  kill "KILL", $pid; waitpid($pid, 0);
  exit(124);
' "$log_file" "$@"
