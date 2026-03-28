#
# Canonical recipe names for migration tests:
# build:
# test:
# run:
# validate:
# doctor:
#
harness_scratch_path := ".build/swiftpm-cache"

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

# Serial preflight recipes for spec closeout work. These intentionally avoid
# parallel runs because the shared scratch-path cache can distort coverage data
# when multiple harness processes overlap in the same worktree.
preflight-swiftpm:
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
