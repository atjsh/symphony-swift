# Server Target Split

## Status

- State: refresh pass updated against the live package manifest and server split tests on 2026-03-28.
- Confidence: the package/target split and source-level boundary checks are verified; this refresh did not rerun the full host-runtime server suite.
- Inventory: keep this task slug; this pass did not justify splitting, merging, creating, or deleting a migration-status task.

## Spec refs

- `SPEC.md` 1
- `SPEC.md` 4.4
- `SPEC.md` 20.3

## Verified in implementation/tests

- The root package manifest publishes `SymphonyServerCore`, `SymphonyServer`, and the `symphony-server` executable wrapper target.
  Evidence: `Package.swift` and `Tests/SymphonyServerTests/ServerPackageMigrationTests.swift`.
- Canonical source and test roots exist for `SymphonyServerCore`, `SymphonyServer`, and `SymphonyServerCLI`, and the removed `SymphonyRuntime` source root is absent.
  Evidence: `Package.swift` and `Tests/SymphonyServerTests/ServerPackageMigrationTests.swift`.
- The split boundary is enforced in source: `SymphonyServerCore` stays free of Hummingbird, HummingbirdWebSocket, and SQLite imports; `SymphonyServerCLI` stays a thin wrapper around `SymphonyServer`; host integration imports live under `SymphonyServer`.
  Evidence: `Sources/SymphonyServerCore`, `Sources/SymphonyServer`, `Sources/SymphonyServerCLI/main.swift`, and `Tests/SymphonyServerTests/ServerPackageMigrationTests.swift`.
- The CLI entry point remains a thin bootstrap wrapper rather than a policy layer.
  Evidence: `Sources/SymphonyServerCLI/main.swift` and `Tests/SymphonyServerTests/ServerPackageMigrationTests.swift`.
- The canonical server executable name remains `symphony-server`.
  Evidence: `Package.swift`, `Tests/SymphonyServerTests/ServerPackageMigrationTests.swift`, and `Tests/SymphonyServerCLITests/SymphonyServerMainTests.swift`.

## Drift / residual gaps

- This refresh reran the targeted package-split verification, not the full host-runtime test matrix. Existing host-runtime coverage still lives in the broader server suite, but it was not freshly revalidated as part of this documentation pass.
- No additional migration-status task is needed yet; the remaining work is runtime revalidation, not target-boundary inventory.

## Next update

- Re-run the broader server host and CLI suites if the split boundary moves again or if new host integrations are added.
- Keep this task slug until any future boundary regressions or lingering `SymphonyRuntime` compatibility shims are either removed or intentionally documented.
