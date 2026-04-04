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

preflight-app:
    just validate SymphonySwiftUIApp

preflight-closeout:
    just preflight-swiftpm
    just preflight-app
