extends "res://addons/gut/test.gd"

## Smoke test — proves the GUT harness is installed and runnable.
##
## This is intentionally trivial: a single passing assertion. If this test
## shows up green in a headless GUT run, the harness is wired correctly and
## real test suites under tests/<system>/ can be added with confidence.
## See tests/README.md for install + run instructions.


func test_harness_runs() -> void:
	assert_eq(1 + 1, 2, "Basic arithmetic should hold — proves GUT is executing assertions.")
