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
  # or a 10-second period with no new "passed/failed" test results after
  # at least one test was observed.
  my $elapsed = 0;
  my $last_result_time = 0;
  my $prev_count = 0;
  my $stable_since = 0;

  while ($elapsed < $timeout) {
    my $w = waitpid($pid, WNOHANG);
    if ($w > 0) {
      my $code = $? >> 8;
      my $sig  = $? & 127;
      exit($sig ? 128 + $sig : $code);
    }

    # Every 2 seconds, check log for completion signals
    if ($elapsed > 5 && $elapsed % 2 == 0 && -f $log) {
      if (open my $fh, "<", $log) {
        my $tail = "";
        my $size = -s $fh;
        if ($size > 8192) { seek($fh, -8192, 2); }
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

        # Count test results to detect hanging after completion
        my $cur_count = () = $tail =~ /Test \S+\(\) (?:passed|failed)/g;
        if ($cur_count > 0 && $cur_count == $prev_count) {
          $stable_since++ ;
          # If no new test results for 15 seconds, tests are done; process is hanging
          if ($stable_since >= 8) {
            my $failed = () = $tail =~ /Test \S+\(\) failed/g;
            kill "TERM", $pid; sleep 1; kill "KILL", $pid; waitpid($pid, 0);
            exit($failed > 0 ? 1 : 0);
          }
        } else {
          $stable_since = 0;
          $prev_count = $cur_count;
        }
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
    if ($passed > 0 && $failed == 0) { exit(0); }
    if ($failed > 0) { exit(1); }
  }
  exit(124);
' "$log_file" "$@"
