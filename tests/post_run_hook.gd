extends "res://addons/gut/hook_script.gd"

const Coverage = preload("res://addons/coverage/Coverage.gd")
const Other = preload("../Other.gd")

const COVERAGE_TARGET := 74.0
const FILE_TARGET := 33.0
# Instrumented code performance should be within this margin of uninstrumented performance
const PERFORMANCE_MARGIN := 1.8

func run():
	var coverage = Coverage.instance()
	var coverage_file := OS.get_environment("COVERAGE_FILE") if OS.has_environment("COVERAGE_FILE") else ""
	if coverage_file:
		coverage.save_coverage_file(coverage_file)
	coverage.set_coverage_targets(COVERAGE_TARGET, FILE_TARGET)
	var verbosity = Coverage.Verbosity.FailingFiles
	var logger = gut.get_logger()
	var other := Other.new()
	assert(Other.source_code.match("*Coverage.gd*"), "Other script should be instrumented")
	var instrumented_time = other.performance_test()
	var instrumented_source = Other.source_code
	coverage.finalize(verbosity)
	assert(!Other.source_code.match("*Coverage.gd*"), "Other script should no longer be instrumented")
	var uninstrumented_time = other.performance_test()
	var performance_loss := (float(instrumented_time) / float(uninstrumented_time))
	gut.set_log_level(gut.LOG_LEVEL_ALL_ASSERTS)
	var performance_passing := performance_loss < PERFORMANCE_MARGIN
	if !performance_passing:
		logger.failed(
			"%s\nInstrumented performance was not good enough.\n  Instrumented: %sus\nUninstrumented: %sus\n%sx > %sx" % [
				instrumented_source.get_slice("performance_test", 1), instrumented_time, uninstrumented_time, performance_loss, PERFORMANCE_MARGIN
			])
		set_exit_code(2)
	else:
		logger.passed("Performance loss for instrumentation: %sx < %s" % [performance_loss, PERFORMANCE_MARGIN])

	var coverage_passing = coverage.coverage_passing()

	if !coverage_passing:
		logger.failed("Coverage target of %.1f%% total (%.1f%% file) was not met" % [COVERAGE_TARGET, FILE_TARGET])
		set_exit_code(2)
	else:
		logger.passed("Coverage target of %.1f%% total, %.1f%% file coverage" % [COVERAGE_TARGET, FILE_TARGET])
