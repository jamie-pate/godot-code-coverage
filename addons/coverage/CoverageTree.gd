extends SceneTree

const Coverage = preload("./Coverage.gd")

func _initialize():
	root.print_tree()
	# need to create the instance because gdscript static functions have no access to their own scripts
	Coverage.new(self).instrument_autoloads().enforce_node_coverage()
	var args = OS.get_cmdline_args()
	for a in args:
		if a.begins_with('--scene='):
			_run_scene(a.replace('--scene=', ''))

func _run_scene(resource_path: String):
	root.print_tree()
	var packed_scene : PackedScene = load(resource_path)
	Coverage.get_instance().instrument_scene_scripts(packed_scene)
	var scene = packed_scene.instantiate()
	root.add_child(scene)

func _finalize():
	var coverage = Coverage.get_instance()
	var coverage_file := OS.get_environment("COVERAGE_FILE") if OS.has_environment("COVERAGE_FILE") else ""
	if coverage_file:
		coverage.save_coverage_file(coverage_file)
	Coverage.finalize(Coverage.Verbosity.AllFiles)
