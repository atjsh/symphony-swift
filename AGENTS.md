# Agent Workflow

This repository is being re-architected toward the single-package `SymphonyHarness`
layout described in `plan.md`. Until the code fully catches up, treat the rules
below as the required target contract for migration work.

This repository uses a test-first workflow for all changes.

## Required order of work

1. Define or update the relevant interfaces, subject mappings, types, and test cases first.
2. Write failing tests before implementation for new behavior.
3. Implement only after the tests and type boundaries make the change explicit.
4. Run the targeted validations for the touched area before asking for integration.

## Target architecture contract

- Keep exactly one root `Package.swift`.
- Do not add or preserve a shell package under `Tools/`.
- Do not add or preserve `project.yml` or any XcodeGen-driven source-of-truth flow.
- The canonical final target names are:
  - `SymphonyShared`
  - `SymphonyServerCore`
  - `SymphonyServer`
  - `SymphonyServerCLI`
  - `SymphonyHarness`
  - `SymphonyHarnessCLI`
  - `SymphonySwiftUIApp`
  - `SymphonySwiftUIAppTests`
  - `SymphonySwiftUIAppUITests`
- The root `Package.swift` is authoritative for `SymphonyShared`,
  `SymphonyServerCore`, `SymphonyServer`, `SymphonyServerCLI`,
  `SymphonyHarness`, and `SymphonyHarnessCLI`.
- The checked-in `Symphony.xcworkspace` / `SymphonyApps.xcodeproj` are
  authoritative for `SymphonySwiftUIApp`, `SymphonySwiftUIAppTests`, and
  `SymphonySwiftUIAppUITests`.
- There are no backward-compatibility aliases for the old implementation identifiers
  `SymphonyBuild`, `SymphonyBuildCore`, `SymphonyBuildCLI`, `SymphonyRuntime`,
  `SymphonyClientUI`, `Symphony`, `SymphonyTests`, `SymphonyUITests`, or
  `symphony-build`.
- Keep `Symphony.xcworkspace` and `SymphonyApps.xcodeproj` filenames stable while
  migrating the app targets, schemes, and bundles inside the project.
- The app display name remains `Symphony`.
- The repo must not commit a fixed signing identity or `DEVELOPMENT_TEAM` value.
- Former `SymphonyClientUI` production code belongs under
  `Applications/SymphonySwiftUIApp`, and its test coverage belongs under
  `Applications/SymphonySwiftUIAppTests`.
- `SymphonyRuntime` is removed as a public target. Pure orchestration, policy,
  and state logic belongs in `SymphonyServerCore`; host/runtime integrations
  belong in `SymphonyServer`; `SymphonyServerCLI` remains a thin executable
  wrapper.
- Only server targets may depend on `Hummingbird`, `HummingbirdWebSocket`, or
  `Yams`.
- `SymphonyHarness` may depend on `SymphonyShared` and harness-internal helpers,
  but never on server-only packages.
- Only `SymphonyHarnessCLI` may depend on `ArgumentParser`.

## Worktree policy

- Every writing sub-agent must use a dedicated git worktree.
- Worktree ownership must be explicit and disjoint by file or module.
- Main integration happens in the primary worktree only after the worker branch is green.
- Do not let multiple agents edit the same file concurrently.

## Commit policy

- Keep commit topics small and green.
- Tests and implementation may be developed incrementally in a topic branch, but they
  should be committed together only after the topic passes.
- Do not inherit the current git index blindly. Stage intentionally for each commit.
- The repository-level pre-commit harness is authoritative once installed. Do not bypass
  it with `--no-verify` unless the user explicitly tells you to do so for a one-off
  emergency.
- The intended contributor entrypoint is `just`. Use `swift run harness ...` only as the
  low-level fallback or while the migration branch is still wiring `just`.
- The final-state pre-commit hook must run `just validate`, not a shell-package wrapper.
- Do not reintroduce `--package-path Tools/SymphonyBuildPackage` or
  `--scratch-path .build/symphony-build-cli` into operator-facing guidance.

## Command contract

- The canonical public CLI surface is:
  - `harness build <subjects...>`
  - `harness test [subjects...]`
  - `harness run <subject>`
  - `harness validate [subjects...]`
  - `harness doctor`
- The canonical contributor UX is:
  - `just build <subjects...>`
  - `just test [subjects...]`
  - `just run <subject>`
  - `just validate [subjects...]`
  - `just doctor`
- `just` is the preferred human-facing layer and shells out to `swift run harness ...`.
- `test` and `validate` accept production subjects and explicit test subjects.
- `build` accepts buildable production subjects only.
- `run` accepts runnable subjects only.
- Runnable subjects are `SymphonyServerCLI` and `SymphonySwiftUIApp`.
- The human-facing server executable product remains `symphony-server`.
- `SymphonyServer` is a buildable and testable host layer, not a direct run
  subject. Server execution goes through `SymphonyServerCLI`.
- There is no subject hierarchy. In particular, `SymphonyServer` does not implicitly include
  `SymphonyServerCLI`, and `SymphonySwiftUIApp` does not implicitly include
  `SymphonySwiftUIAppUITests`.

## Default subject semantics

- The default `just test` subject set is:
  - `SymphonyShared`
  - `SymphonyServerCore`
  - `SymphonyServer`
  - `SymphonyServerCLI`
  - `SymphonyHarness`
  - `SymphonyHarnessCLI`
  - `SymphonySwiftUIApp` when Xcode is available
- The default `just validate` subject set is the same list plus the repository-wide policy
  for coverage, artifacts, and environment checks.
- `SymphonySwiftUIAppUITests` is always explicit-only.
- Production subjects map to default test companions only:
  - `SymphonyShared` -> `SymphonySharedTests`
  - `SymphonyServerCore` -> `SymphonyServerCoreTests`
  - `SymphonyServer` -> `SymphonyServerTests`
  - `SymphonyServerCLI` -> `SymphonyServerCLITests`
  - `SymphonyHarness` -> `SymphonyHarnessTests`
  - `SymphonyHarnessCLI` -> `SymphonyHarnessCLITests`
  - `SymphonySwiftUIApp` -> `SymphonySwiftUIAppTests`
- Multi-subject runs execute in parallel by default.
- Subjects that require exclusive simulator or UI-test destinations must be auto-serialized by
  the scheduler instead of failing from destination contention.

## Required validation

- The minimum final-state gate for any code change is:
  - `just validate`
  - `just doctor`
- The low-level fallback is:
  - `swift run harness validate`
  - `swift run harness doctor`
- `validate` and the final-state pre-commit hook enforce `100%` first-party source
  coverage under the current target names and paths. Tests, generated files, and
  dependency sources are excluded from that threshold.
- On hosts without Xcode:
  - package, server, and harness subjects must still pass
  - app build, test, and run flows must report explicit unsupported or skipped outcomes
  - those capability-aware skips are successful behavior, not hard failures
- `doctor` must report missing `just` or missing Xcode clearly and deterministically.
- If the branch is mid-migration and the final commands are not wired yet, continue working
  toward them; do not preserve the old `symphony-build` command shape as the steady state.

## Targeted validation by area

- If the change touches subject parsing, command routing, scheduling, coverage policy, artifact
  policy, or validation plumbing, run:
  - `just test SymphonyHarness SymphonyHarnessCLI`
  - `just validate SymphonyHarness SymphonyHarnessCLI`
  - `just doctor`
- If the change touches server layering, server subject mapping, or the
  `SymphonyServerCore` / `SymphonyServer` / `SymphonyServerCLI` split, run:
  - `just test SymphonyServerCore SymphonyServer SymphonyServerCLI`
  - `just validate SymphonyServerCore SymphonyServer SymphonyServerCLI`
- If the change touches shared contracts or values, run:
  - `just test SymphonyShared`
  - `just validate SymphonyShared`
- If the change touches the app target rename, app test bundles, simulator scheduling,
  endpoint injection, or signing cleanup, run:
  - `just build SymphonySwiftUIApp`
  - `just test SymphonySwiftUIApp`
  - `just validate SymphonySwiftUIApp`
  - `just test SymphonySwiftUIAppUITests` when the change explicitly touches UI-test behavior
- If the change touches the root package graph, target isolation, external dependency ownership,
  or the removal of `SymphonyClientUI` / `SymphonyRuntime`, run:
  - `swift test`
  - `just validate`

## Artifact inspection

- Validation is not complete until the produced harness artifacts are inspected. A zero exit
  code alone is insufficient for harness changes.
- Use the shared run root reported by `harness` or `just` rather than guessing paths.
- The canonical harness artifact root is `.build/harness`.
- Each run writes a shared summary plus per-subject artifacts under one run root.
- Inspect artifacts in this order:
  1. shared `summary.txt`
  2. shared `index.json`
  3. each touched subject's `summary.txt`
  4. each touched subject's `index.json`
  5. each touched subject's `coverage.txt` and `coverage.json` when coverage is enabled
  6. each touched subject's `process-stdout-stderr.txt`
  7. `diagnostics/` and `attachments/` when summaries or indexes report export anomalies
- Successful Xcode-backed subject runs must not report a missing result bundle.
- Missing recording, screenshot, or UI-tree exports are acceptable only when the summary or
  index records them as optional anomalies.

## Implementation defaults

- Prefer explicit over clever.
- Flag and remove repetition aggressively.
- Add tests for edge cases rather than relying on manual verification alone.
- Keep abstractions shallow unless duplication or coupling clearly justifies a new layer.
- Keep server-only packages isolated to server targets.
- Keep `ArgumentParser` isolated to `SymphonyHarnessCLI`.
- In async runtime paths and Swift Testing helpers, do not block the cooperative executor with
  `DispatchSemaphore.wait()` or similar synchronous waits. Prefer async-safe continuations,
  streams, or other awaited coordination primitives for startup handshakes and long-lived
  fixtures.
