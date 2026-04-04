# Agent Workflow

This repository is being re-architected toward the single-package
layout described in `SPEC.md`. Until the code fully catches up, treat the rules
below as the required target contract for migration work.

## Required order of work

1. Define or update the relevant interfaces, subject mappings, types, and test cases first.
2. Write failing tests before implementation for new behavior.
3. Implement only after the tests and type boundaries make the change explicit.
4. Run the targeted validations for the touched area before asking for integration.

## Commit policy

- Keep commit topics small and green.

## Implementation defaults

- Prefer explicit over clever.
- Flag and remove repetition aggressively.
- Add tests for edge cases rather than relying on manual verification alone.
- Keep abstractions shallow unless duplication or coupling clearly justifies a new layer.

## Terminal command safety

Coding agents must follow these rules to avoid commands that hang
indefinitely, which blocks the entire agent session with no recovery path.

### Never pipe swift or just output

Shell pipes (`| tail`, `| grep`, `| head`) cause **pipe-buffer deadlocks**
when the producer writes to both stdout and stderr. Swift tooling is
block-buffered when connected to a pipe — the 64 KB pipe buffer fills,
the writer blocks, the reader waits for EOF, and both sides stall.

```
# WRONG — will hang
swift test --filter SymphonyServerTests 2>&1 | tail -20
swift build 2>&1 | grep error

# CORRECT — let the agent framework truncate output
swift test --filter SymphonyServerTests
swift build
```

When post-processing is truly needed, redirect to a file first, then
read the file in a separate command:

```
swift test 2>&1 > /tmp/test-output.txt; tail -20 /tmp/test-output.txt
```

### Never run concurrent SwiftPM commands

SwiftPM holds an exclusive file lock on the scratch-path directory
(`.build/.lock` or `.build/swiftpm-cache/.lock`). A second SwiftPM
process targeting the same scratch path will wait for the lock
indefinitely.

- Wait for each `swift build`, `swift test`, or `just` recipe to
  complete before starting the next one.
- Do not run `just lint` while a `swift test` or `swift build` is
  active — `just lint` uses the default `.build` lock.
- When recovering from a stuck command, kill the terminal and wait
  2 seconds before retrying. Do not start a new command in a
  different terminal against the same scratch path.

### Prefer just recipes over raw swift commands

The `justfile` recipes use a consistent `--scratch-path .build/swiftpm-cache`
and the harness wraps execution with structured output and artifact
management.

```
# Preferred
just test SymphonyServer
just lint
just coverage SymphonyServer

# Acceptable when just is unavailable
swift test --scratch-path .build/swiftpm-cache --filter SymphonyServerTests
swift build --scratch-path .build/swiftpm-cache
```

### Timeout guidelines

| Command | Safe timeout |
|---|---|
| `swift build` (warm) | 60 s |
| `swift build` (cold) | 180 s |
| `just test <Subject>` / `swift test --filter` (single suite) | 120 s |
| `swift test` (all suites) | 300 s |
| `just lint` | 120 s |
| `just validate` / `xcodebuild test` | 600 s |

When a timeout fires, **kill the terminal** before retrying. Do not
assume the process exited — SwiftPM may still hold the scratch-path lock.

### Recovery from a hung terminal

1. Kill the terminal (or the background process ID).
2. Wait 2 seconds for lock files to release.
3. Retry the command **without pipes** in a fresh terminal.
4. If the same command hangs twice, check for a competing SwiftPM
   process: `pgrep -fl swift`.
