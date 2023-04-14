extends "res://addons/gut/test.gd"

# Instrumented code performance should be within this margin of uninstrumented performance
const PERFORMANCE_MARGIN := 1.8

const scene = preload("res://Spatial.tscn")
const Coverage = preload("res://addons/coverage/Coverage.gd")
const Other = preload("res://Other.gd")

func test_autoload_coverage():
	assert_true(Autoload1._initted)
	assert_eq(Autoload1._ready, '1')
	assert_eq(Autoload2._counter, '2')
	var node = add_child_autoqfree(scene.instance())
	node.auto_quit = false
	yield(yield_to(node, "done", 5000), YIELD)
	assert_signal_emitted(node, "done")
	assert_true(Autoload1._initted)
	assert_eq(Autoload1._ready, '1')
	assert_eq(Autoload2._counter, '3')

	assert_eq(Autoload1.other._initted, 1)

func test_performance():
	var coverage: Coverage = Coverage.instance()
	var collector: Coverage.ScriptCoverageCollector = coverage.get_coverage_collector(Other.resource_path)
	var logger = get_logger()
	var other := Other.new()
	assert_true(Other.source_code.match("*Coverage.gd*"), "Other script should be instrumented")
	var instrumented_source = Other.source_code
	var instrumented_time = other.performance_test()
	collector.set_instrumented(false)
	assert_false(Other.source_code.match("*Coverage.gd*"), "Other script should no longer be instrumented")
	var uninstrumented_time = other.performance_test()
	collector.set_instrumented(true)
	assert_true(Other.source_code.match("*Coverage.gd*"), "Other script should be instrumented")
	var performance_loss := (float(instrumented_time) / float(uninstrumented_time))
	var performance_passing := performance_loss < PERFORMANCE_MARGIN
	assert_gt(performance_loss, 1.2, "Performance loss should be measureable")
	assert_lt(performance_loss, PERFORMANCE_MARGIN, "Performance loss for instrumentation: %sx < %s" % [performance_loss, PERFORMANCE_MARGIN])
	if !performance_passing:
		logger.failed(
			"%s\nInstrumented performance was not good enough.\n  Instrumented: %sus\nUninstrumented: %sus\n%sx > %sx" % [
				instrumented_source.get_slice("performance_test", 1), instrumented_time, uninstrumented_time, performance_loss, PERFORMANCE_MARGIN
			])
