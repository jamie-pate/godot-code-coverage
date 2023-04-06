extends "res://addons/gut/test.gd"

const scene = preload("res://Spatial.tscn")

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
