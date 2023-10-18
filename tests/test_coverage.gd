extends "res://addons/gut/test.gd"

# Instrumented code performance should be within this margin of uninstrumented performance
const PERFORMANCE_MARGIN := 1.85

const scene = preload("res://Spatial.tscn")
const Coverage = preload("res://addons/coverage/Coverage.gd")
const Other = preload("res://Other.gd")

static var OtherScript := Other as GDScript

func test_autoload_coverage():
	assert_true(Autoload1._initted)
	assert_eq(Autoload1._ready_value, '1')
	assert_eq(Autoload2._counter, '2')
	var node = add_child_autoqfree(scene.instantiate())
	node.auto_quit = false
	await wait_for_signal(node.done, 5000)
	assert_signal_emitted(node, "done")
	assert_true(Autoload1._initted)
	assert_eq(Autoload1._ready_value, '1')
	assert_eq(Autoload2._counter, '3')

	assert_eq(Autoload1.other._initted, 1)

func test_performance():
	var coverage: Coverage = Coverage.get_instance()
	var collector: Coverage.ScriptCoverageCollector = coverage.get_coverage_collector(OtherScript.resource_path)
	var logger = get_logger()
	var other := Other.new()
	assert_true(OtherScript.source_code.match("*Coverage.gd*"), "Other script should be instrumented")
	var instrumented_source = (Other as GDScript).source_code
	var instrumented_time = other.performance_test()
	collector.set_instrumented(false)
	assert_false(OtherScript.source_code.match("*Coverage.gd*"), "Other script should no longer be instrumented")
	var uninstrumented_time = other.performance_test()
	collector.set_instrumented(true)
	assert_true(OtherScript.source_code.match("*Coverage.gd*"), "Other script should be instrumented")
	var performance_loss := (float(instrumented_time) / float(uninstrumented_time))
	var performance_passing := performance_loss < PERFORMANCE_MARGIN
	assert_gt(performance_loss, 1.2, "Performance loss should be measureable")
	assert_lt(performance_loss, PERFORMANCE_MARGIN, "Performance loss for instrumentation: %sx < %s" % [performance_loss, PERFORMANCE_MARGIN])
	if !performance_passing:
		logger.failed(
			"%s\nInstrumented performance was not good enough.\n  Instrumented: %sus\nUninstrumented: %sus\n%sx > %sx" % [
				instrumented_source.get_slice("performance_test", 1), instrumented_time, uninstrumented_time, performance_loss, PERFORMANCE_MARGIN
			])
