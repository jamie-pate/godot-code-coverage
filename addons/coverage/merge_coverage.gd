extends MainLoop

const Coverage = preload("./coverage.gd")

var _quit := false
var _exit_code := 0


func _print_usage():
	print(
		"""Usage: godot -s res://addons/coverage/merge_coverage.gd  [flags] coverage1.json coverage2.json [...coverageN.json]
	Merges multiple input
	flags:
		--verbosity 3 : Set the verbosity of the coverage output. See Coverage.gd:Verbosity for levels.
		--target 100 : set the coverage target, exit with failure if the target isn't met over all files.
		--file-target 100 : set the coverage target for individual files. exit with failure if the target isn't met.
		--output-file output.json : Save the merged coverage to this file.
	"""
	)


func _initialize():
	var coverage := Coverage.new(self)
	var args := Array(OS.get_cmdline_args())
	var coverage_target := INF
	var file_target := INF
	var output_filename := ""
	var verbosity: int = Coverage.Verbosity.FAILING_FILES
	while len(args) && args[0].begins_with("-"):
		var flag = args.pop_front()
		match flag:
			"-s", "--script":
				if len(args):
					args.pop_front()
			"--target":
				if len(args):
					coverage_target = float(args.pop_front())
			"--file-target":
				if len(args):
					file_target = float(args.pop_front())
			"--output-file":
				if len(args):
					output_filename = args.pop_front()
			"--verbosity":
				if len(args):
					verbosity = int(args.pop_front())
	var files := args
	if len(files) < 2:
		_print_usage()
		quit()
		return
	var reports := []
	var result := true
	for filename in files:
		if !coverage.merge_from_coverage_file(filename, false):
			result = false
	if !result:
		quit(1)
		return
	if output_filename:
		coverage.save_coverage_file(output_filename)
	coverage.set_coverage_targets(coverage_target, file_target)
	coverage.finalize(verbosity)
	if !coverage.coverage_passing():
		quit(1)
	else:
		quit()


func quit(exit_code := 0):
	_quit = true
	_exit_code = exit_code


func _process(_delta):
	if _quit:
		# Would prefer OS.set_exit_code(_exit_code), but it was removed...
		# see https://github.com/godotengine/godot/issues/90646
		var st := SceneTree.new()
		st.quit(_exit_code)
		st.free()
	return _quit
