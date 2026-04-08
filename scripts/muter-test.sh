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

timeout_secs="${MUTER_TEST_TIMEOUT:-600}"

# Run swift test with timeout; kill after timeout + grace period.
# We use perl because macOS doesn't ship GNU timeout / gtimeout.
#
# IMPORTANT: When the child is killed by a signal (not a normal exit),
# $? >> 8 is 0. We must detect signal-kills and return non-zero so that
# Muter treats crashes as test failures, not passes.
_MUTER_TIMEOUT="$timeout_secs" _MUTER_LOG="$log_file" perl -e '
  use POSIX ":sys_wait_h";
  my $timeout = $ENV{"_MUTER_TIMEOUT"};
  my $log     = $ENV{"_MUTER_LOG"};
  my $pid = fork();
  if ($pid == 0) {
    open STDOUT, ">", $ARGV[0] or die;
    open STDERR, ">&STDOUT";
    exec("/usr/bin/swift", "test", @ARGV[1..$#ARGV]) or die "exec: $!";
  }

  # Poll: wait for child exit OR detect test completion in the log file.
  # swiftpm-testing-helper often hangs after all tests finish, so we check
  # the log every second for a "Test run with ... passed/failed" summary
  # or a prolonged period where the log stops growing (no new output).
  my $elapsed = 0;
  my $prev_size = 0;
  my $stable_since = 0;

  while ($elapsed < $timeout) {
    my $w = waitpid($pid, WNOHANG);
    if ($w > 0) {
      my $code = $? >> 8;
      my $sig  = $? & 127;
      exit($sig ? 128 + $sig : $code);
    }

    # Every 2 seconds, check log for completion signals
    if ($elapsed > 10 && $elapsed % 2 == 0 && -f $log) {
      my $cur_size = -s $log;

      if ($cur_size > 8192) {
        if (open my $fh, "<", $log) {
          seek($fh, -8192, 2);
          my $tail = "";
          { local $/; $tail = <$fh>; }
          close $fh;

          # Check for summary line (definitive)
          if ($tail =~ /Test run with \d+ tests? in \d+ suites? passed/) {
            kill "TERM", $pid; sleep 1; kill "KILL", $pid; waitpid($pid, 0);
            exit(0);
          }
          if ($tail =~ /Test run with \d+ tests? in \d+ suites? failed/) {
            kill "TERM", $pid; sleep 1; kill "KILL", $pid; waitpid($pid, 0);
            exit(1);
          }
        }
      }

      # Use log FILE SIZE to detect that output has stopped (process hanging).
      # Previous approach counted test-result lines in the 8KB tail window;
      # that stabilises even while tests are still running because old lines
      # scroll out of the window at the same rate new ones appear.
      if ($cur_size > 0 && $cur_size == $prev_size) {
        $stable_since++;
        # No new output for 60 seconds → tests are done; process is hanging.
        if ($stable_since >= 30) {
          # Read the FULL log to classify (failures may be outside the tail).
          my $exit_code = 0;
          if (open my $fh, "<", $log) {
            my $content = "";
            { local $/; $content = <$fh>; }
            close $fh;
            my $failed = () = $content =~ /Test \S+\(\) failed/g;
            # Swift Testing logs "recorded an issue" for expectation
            # failures. When the process hangs before printing the
            # final "Test X() failed" line, we must still detect
            # these as test failures so Muter counts the kill.
            my $issues = () = $content =~ /recorded an issue/g;
            $exit_code = 1 if $failed > 0 || $issues > 0;
          }
          kill "TERM", $pid; sleep 1; kill "KILL", $pid; waitpid($pid, 0);
          exit($exit_code);
        }
      } else {
        $stable_since = 0;
        $prev_size = $cur_size;
      }
    }

    sleep 1; $elapsed++;
  }

  # Hard timeout: kill and inspect log
  kill "TERM", $pid; sleep 2;
  kill "KILL", $pid; waitpid($pid, 0);

  if (open my $fh, "<", $log) {
    my $content = "";
    { local $/; $content = <$fh>; }
    close $fh;
    my $passed = () = $content =~ /Test \S+\(\) passed/g;
    my $failed = () = $content =~ /Test \S+\(\) failed/g;
    my $issues = () = $content =~ /recorded an issue/g;
    if ($failed > 0 || $issues > 0) { exit(1); }
    if ($passed > 0) { exit(0); }
  }
  exit(124);
' "$log_file" "$@"
