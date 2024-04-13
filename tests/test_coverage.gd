extends "res://addons/gut/test.gd"

# Instrumented code performance should be within this margin of uninstrumented performance
const PERFORMANCE_MARGIN := 2.1

const SPATIAL_SCENE = preload("res://spatial.tscn")
const Coverage = preload("res://addons/coverage/coverage.gd")
const Other = preload("res://other.gd")


func test_autoload_coverage():
	assert_true(Autoload1._initted)
	assert_true(Autoload1.is_node_ready())
	assert_eq(Autoload2._counter, "2")
	var node = add_child_autoqfree(SPATIAL_SCENE.instantiate())
	node.auto_quit = false
	await wait_for_signal(node.done, 5000)
	assert_signal_emitted(node, "done")
	assert_true(Autoload1._initted)
	assert_true(Autoload1.is_node_ready())
	assert_eq(Autoload2._counter, "3")

	assert_eq(Autoload1.other._initted, 1)


func test_performance():
	var coverage: Coverage = Coverage.instance
	var collector: Coverage.ScriptCoverageCollector = coverage.get_coverage_collector(
		"res://other.gd"
	)
	var logger = get_logger()
	var other := Other.new()
	var other_script := other.get_script() as GDScript
	assert_true(
		other_script.source_code.match("*coverage.gd*"), "Other script should be instrumented"
	)
	var instrumented_source = other_script.source_code
	var instrumented_time = other.performance_test()
	collector.set_instrumented(false)
	assert_false(
		other.get_script().source_code.match("*coverage.gd*"),
		"Other script should no longer be instrumented"
	)
	var uninstrumented_time = other.performance_test()
	collector.set_instrumented(true)
	assert_true(
		other_script.source_code.match("*coverage.gd*"), "Other script should be instrumented"
	)
	var performance_loss := float(instrumented_time) / float(uninstrumented_time)
	var performance_passing := performance_loss < PERFORMANCE_MARGIN
	assert_gt(performance_loss, 1.2, "Performance loss should be measureable")
	assert_lt(
		performance_loss,
		PERFORMANCE_MARGIN,
		(
			"Performance loss for instrumentation: %.2fx < %.2f"
			% [performance_loss, PERFORMANCE_MARGIN]
		)
	)
	if !performance_passing:
		(
			logger
			. failed(
				(
					"%s\nInstrumented performance was not good enough.\n  Instrumented: %sus\nUninstrumented: %sus\n%sx > %sx"
					% [
						instrumented_source.get_slice("performance_test", 1),
						instrumented_time,
						uninstrumented_time,
						performance_loss,
						PERFORMANCE_MARGIN
					]
				)
			)
		)
