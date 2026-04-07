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
set -euo pipefail
export PATH="/usr/bin:/usr/local/bin:/opt/homebrew/bin:$PATH"

log_dir="${PWD}/muter_logs"
mkdir -p "$log_dir"
log_file="${log_dir}/swift-test-$(date +%s).log"

# Run swift test with timeout; kill after testSuiteTimeout + grace period.
# We use perl because macOS doesn't ship GNU timeout / gtimeout.
perl -e '
  use POSIX ":sys_wait_h";
  my $timeout = 240;
  my $pid = fork();
  if ($pid == 0) {
    open STDOUT, ">", $ARGV[0] or die;
    open STDERR, ">&STDOUT";
    exec("/usr/bin/swift", "test", @ARGV[1..$#ARGV]) or die "exec: $!";
  }
  my $elapsed = 0;
  while ($elapsed < $timeout) {
    my $w = waitpid($pid, WNOHANG);
    if ($w > 0) { exit($? >> 8); }
    sleep 1; $elapsed++;
  }
  kill "TERM", $pid; sleep 2;
  kill "KILL", $pid; waitpid($pid, 0);
  exit($? >> 8);
' "$log_file" "$@"
