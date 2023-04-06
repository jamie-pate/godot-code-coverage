extends "res://addons/gut/test.gd"

const scene = preload("res://Spatial.tscn")

func test_coverage():
	var node = add_child_autoqfree(scene.instance())
	node.auto_quit = false
	yield(yield_to(node, "done", 5000), YIELD)
	assert_signal_emitted(node, "done")
