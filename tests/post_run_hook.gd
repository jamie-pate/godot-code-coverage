extends "res://addons/gut/hook_script.gd"

const Coverage = preload("res://addons/coverage/Coverage.gd")

const COVERAGE_TARGET = 91.0

func run():
	var coverage_percent = Coverage.instance().coverage_percent()
	Coverage.instance().finalize(coverage_percent < COVERAGE_TARGET)
	var logger = gut.get_logger()
	if coverage_percent < COVERAGE_TARGET:
		logger.failed("Coverage target of %.1f%% was not met" % [COVERAGE_TARGET])
		set_exit_code(2)
	else:
		gut.set_log_level(gut.LOG_LEVEL_ALL_ASSERTS)
		logger.passed("Coverage target of %.1f%%" % [COVERAGE_TARGET])
