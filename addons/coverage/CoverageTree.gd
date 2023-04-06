extends SceneTree

const Coverage = preload("./Coverage.gd")

func _initialize():
	# need to create the instance because gdscript static functions have no access to their own scripts
	Coverage.new(self).instrument_autoloads().enforce_node_coverage()
	var args = OS.get_cmdline_args()
	for a in args:
		if a.begins_with('--scene='):
			_run_scene(a.replace('--scene=', ''))
	print("initialize")

func _run_scene(resource_path: String):
	var packed_scene : PackedScene = load(resource_path)
	Coverage.instance().instrument_scene_scripts(packed_scene)
	var scene = packed_scene.instance()
	root.add_child(scene)

func _finalize():
	print("finalize")
	Coverage.finalize(true)
