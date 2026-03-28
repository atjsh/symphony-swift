#
# Canonical recipe names for migration tests:
# build:
# test:
# run:
# validate:
# doctor:
#
build *subjects:
    swift run harness build {{subjects}}

test *subjects:
    swift run harness test {{subjects}}

run subject='' *rest:
    swift run harness run {{subject}} {{rest}}

validate *subjects:
    swift run harness validate {{subjects}}

doctor:
    swift run harness doctor
