#
# Canonical recipe names for migration tests:
# build:
# test:
# run:
# validate:
# doctor:
#
harness_scratch_path := ".build/swiftpm-cache"

materialize-go-enry:
    swift run --quiet --scratch-path {{harness_scratch_path}} harness materialize-go-enry

build *subjects:
    swift run --quiet --scratch-path {{harness_scratch_path}} harness build {{subjects}}

test *subjects:
    swift run --quiet --scratch-path {{harness_scratch_path}} harness test {{subjects}}

run subject='' *rest:
    swift run --quiet --scratch-path {{harness_scratch_path}} harness run {{subject}} {{rest}}

validate *subjects:
    swift run --quiet --scratch-path {{harness_scratch_path}} harness validate {{subjects}}

doctor:
    swift run --quiet --scratch-path {{harness_scratch_path}} harness doctor

lint:
    swift package --scratch-path {{harness_scratch_path}} plugin --allow-writing-to-package-directory swiftlint lint

lint-fix:
    swift package --scratch-path {{harness_scratch_path}} plugin --allow-writing-to-package-directory swiftlint --fix

# Kill stale SwiftPM processes to recover from hung terminals or lock contention.
kill-swift:
    pkill -f "swift-test|swift-build|swiftpm-testing-helper|swift-package" 2>/dev/null || true
    sleep 2
    @echo "Cleared stale SwiftPM processes."

coverage *subjects:
    swift run --quiet --scratch-path {{harness_scratch_path}} harness test --enable-code-coverage {{subjects}}

# Serial preflight recipes for spec closeout work. These intentionally avoid
# parallel runs because the shared scratch-path cache can distort coverage data
# when multiple harness processes overlap in the same worktree.
preflight-swiftpm:
    just materialize-go-enry
    just test SymphonyShared
    just test SymphonyServerCore
    just test SymphonyServer
    just test SymphonyServerCLI
    just test SymphonyHarness
    just test SymphonyHarnessCLI
    just test SymphonyXcodeValidation
    just test SymphonyXcodeValidationServerCore
    just test SymphonyXcodeValidationServer

preflight-app:
    just validate SymphonySwiftUIApp

preflight-closeout:
    just preflight-swiftpm
    just preflight-app

# ── Mutation Testing (Muter) ──────────────────────────────────────────

# Muter copies the entire project to a temp directory. The .build/ dir can be
# tens of gigabytes of derived data, so we move it out during the copy, keeping
# only the directories needed for compilation and package resolution:
#   vendor/       – go-enry C library for CGoEnryBridge
#   checkouts/    – SPM checked-out package sources
#   repositories/ – SPM bare git repository cache
#   artifacts/    – SPM binary artifact cache
#   workspace-state.json – SPM workspace resolution state
[private]
muter-run +args:
    #!/usr/bin/env bash
    set -euo pipefail
    stash="/tmp/symphony-muter-build-stash"

    if [[ -d .build ]]; then
      rm -rf "$stash"
      mv .build "$stash"
      mkdir -p .build
      for dir in vendor checkouts repositories artifacts; do
        if [[ -d "$stash/$dir" ]]; then
          cp -a "$stash/$dir" ".build/$dir"
        fi
      done
      if [[ -f "$stash/workspace-state.json" ]]; then
        cp -a "$stash/workspace-state.json" .build/workspace-state.json
      fi
    fi

    trap '[[ -d "$stash" ]] && { rm -rf .build 2>/dev/null; mv "$stash" .build; }' EXIT

    muter {{args}}

# Run full mutation testing across all non-excluded sources.
mutate *flags:
    just muter-run {{flags}}

# Run mutation testing only on specific files (comma-separated or glob).
mutate-files +files:
    just muter-run --files-to-mutate {{files}}

# Run mutation testing only on files changed since the previous commit.
mutate-changed:
    just muter-run --files-to-mutate $(echo "$(git diff --name-only HEAD HEAD~1 | tr '\n' ',')")
