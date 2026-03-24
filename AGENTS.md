# Agent Workflow

This repository uses a test-first workflow for all changes.

## Required order of work

1. Define or update the relevant interfaces, types, and test cases first.
2. Write failing tests before implementation for new behavior.
3. Implement only after the tests and type boundaries make the change explicit.
4. Run the targeted validations for the touched area before asking for integration.

## Worktree policy

- Every writing sub-agent must use a dedicated git worktree.
- Worktree ownership must be explicit and disjoint by file or module.
- Main integration happens in the primary worktree only after the worker branch is green.
- Do not let multiple agents edit the same file concurrently.

## Commit policy

- Keep commit topics small and green.
- Tests and implementation may be developed incrementally in a topic branch, but they should be committed together only after the topic passes.
- Do not inherit the current git index blindly. Stage intentionally for each commit.
- The repository-level pre-commit harness is authoritative once installed. Do not bypass it with `--no-verify` unless the user explicitly tells you to do so for a one-off emergency.
- After cloning a fresh checkout, run `swift run symphony-build hooks install` once so the committed `.githooks/pre-commit` hook is active for that clone and any future worktrees attached to it.

## Required validation

- Minimum gate for any code change:
  - `swift run symphony-build harness`
  - `swift run symphony-build doctor`
- The commit harness is the canonical gate for package-level changes:
  - It runs `swift test --enable-code-coverage`.
  - It measures first-party code coverage from SwiftPM’s exported coverage JSON, filtered to tracked files under `Sources/`.
  - It also runs Xcode-backed coverage passes for the bootstrap client and server products on macOS:
    - `swift run symphony-build coverage --product client --platform macos --json`
    - `swift run symphony-build coverage --product server --json`
  - Test files, generated runners, and checked-out dependency sources are excluded from the threshold calculation.
  - Commits must not proceed if any of the following fall below `50.00%`:
    - first-party SwiftPM source coverage
    - bootstrap client product coverage
    - bootstrap server product coverage
  - The current threshold is intentionally lower than the long-term goal; treat regressions below the current floor as hard failures.
- If the change touches `SymphonyBuildCore`, `SymphonyBuildCLI`, `project.yml`, `Symphony.xcworkspace`, `SymphonyApps.xcodeproj`, or the bootstrap app/server targets, run the dry-run command surface as well:
  - `swift run symphony-build build --product server --dry-run --xcode-output-mode filtered`
  - `swift run symphony-build test --product server --dry-run --xcode-output-mode filtered`
  - `swift run symphony-build run --product server --dry-run --xcode-output-mode quiet`
  - `swift run symphony-build coverage --product server --dry-run --xcode-output-mode filtered`
- If the change touches commit gating, validation plumbing, or agent harness behavior, validate the harness explicitly:
  - `swift run symphony-build harness`
  - `swift run symphony-build harness --minimum-coverage 100` must fail unless every required coverage suite is already at `100.00%`
  - `swift run symphony-build hooks install`
- If the change touches simulator resolution, destination defaults, runtime endpoint injection, or the client bootstrap target, also validate the client path:
  - `swift run symphony-build build --dry-run`
  - `swift run symphony-build run --product client --dry-run`
  - `swift run symphony-build coverage --product client --dry-run`
  - On machines where the default `iPhone 17` destination is ambiguous, those two commands must fail with a clear `ambiguous_simulator_name` error. Use an explicit UDID for all remaining client validations.
  - Use `swift run symphony-build sim list` to select the simulator UDID for explicit client runs.
- If the change touches artifact generation, xcresult export, launch behavior, or any real Xcode invocation path, run the live smoke checks:
  - `swift run symphony-build build --product server --worker 1 --xcode-output-mode filtered`
  - `swift run symphony-build test --product server --worker 1 --xcode-output-mode filtered`
  - `swift run symphony-build run --product server --worker 1 --xcode-output-mode filtered`
  - `swift run symphony-build build --product client --worker 2 --simulator <UDID> --xcode-output-mode filtered`
  - `swift run symphony-build run --product client --worker 2 --simulator <UDID> --xcode-output-mode filtered`
- Always clean up long-lived processes after live verification:
  - Stop detached `SymphonyServer` processes after `run --product server`.
  - Stop the simulator app after `run --product client`.
- Validation is not complete until the produced artifacts are inspected using the canonical checks below. A green exit code without artifact inspection is insufficient for build-tool changes.

## Canonical artifact inspection

- Use the tool itself to resolve artifact roots; do not guess paths manually:
  - `swift run symphony-build artifacts build`
  - `swift run symphony-build artifacts test`
  - `swift run symphony-build artifacts coverage`
  - `swift run symphony-build artifacts run`
  - Use `swift run symphony-build artifacts <build|test|coverage|run> --run <run-id>` when you need a non-latest run.
- Inspect artifacts in this order:
  1. `summary.txt`
  2. `index.json`
  3. `summary.json`
  4. `process-stdout-stderr.txt`
  5. `diagnostics/` and `attachments/` if the summary or index indicates xcresult export issues
- `summary.txt` is the primary human-readable truth source. Confirm:
  - the `invocation` matches the command you intended to run
  - `exit_code` matches the observed outcome
  - `anomalies` only contains expected optional-export entries
  - server host runs use `platform=macOS,arch=<host-arch>` and do not contain the `multiple matching destinations` warning
  - successful runs do not mention `xcresult_summary_export_failed`
- `index.json` is the machine-readable truth source. Confirm with `jq '.anomalies' <index.json>` that:
  - `missing_recording`, `missing_screen_capture`, and `missing_ui_tree` are acceptable when the xcresult did not produce those optional exports
  - `missing_result_bundle` is never acceptable for a successful Xcode-backed run
  - `xcresult_summary_export_failed`, `xcresult_diagnostics_export_failed`, and `xcresult_attachments_export_failed` are build-tool defects unless the test explicitly expects them
  - `simulator_install_failed` and `simulator_launch_failed` are always failures for client launch validation
- Coverage artifacts add two extra canonical outputs:
  - `coverage.txt` is the primary human-readable coverage summary for the `coverage` command family.
  - `coverage.json` is the machine-readable coverage summary derived from `xccov`.
  - For the commit harness, the equivalent machine-readable source is SwiftPM’s exported coverage JSON path printed by `swift test --show-code-coverage-path`, but the rendered `swift run symphony-build harness --json` output is the canonical normalized view.
- `summary.json` must contain exported xcresult JSON for successful Xcode-backed runs. An empty `{}` payload is only acceptable when the run legitimately produced no result bundle and the summary/index record that explicitly.
- `process-stdout-stderr.txt` is the canonical raw transcript for diagnosing filtered output. Use it when:
  - filtered mode suppressed too much detail
  - you need to confirm stale-heartbeat timing
  - you need to inspect the exact xcodebuild, simctl, or launched-process output
- `diagnostics/` and `attachments/` are supporting evidence, not the first stop. Check them when:
  - xcresult export anomalies appear
  - you need to confirm whether screenshots, recordings, or UI trees were actually absent versus failed to export
- For phase-1 bootstrap verification, the canonical “good” artifact state is:
  - build/test/run summaries exist and point at stable `latest` artifact roots
  - `summary.json` is populated from xcresult export
  - only optional-export anomalies remain when the xcresult has no recording, screen capture, or UI tree
  - no destination ambiguity warnings appear in successful host artifacts

## Implementation defaults

- Prefer explicit over clever.
- Flag and remove repetition aggressively.
- Add tests for edge cases rather than relying on manual verification alone.
- Keep abstractions shallow unless duplication or coupling clearly justifies a new layer.
