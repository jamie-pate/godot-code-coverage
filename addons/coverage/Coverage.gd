extends RefCounted

# verbosity levels:
# None: not verbose
# Filenames: coverage for each file,
# FailingFiles: coverage for only files that failed to meet the file coverage target.
# PartialFiles: coverage for each line (except when file coverage is 0%/100%)
# AllFiles: coverage for each line for every file
enum Verbosity {
	None = 0,
	Filenames = 1,
	FailingFiles = 3,
	PartialFiles = 4,
	AllFiles = 5
}

const MAX_QUEUE_SIZE := 10000

class ScriptCoverage:
	extends RefCounted

	var coverage_lines := {}
	# coverage_queue.append() is so far the fastest way to instrument code
	# coverage_queue.append(line_number) seems faster than coverage_lines[i] += 1
	var coverage_queue := []
	var script_path := ""
	var source_code := ""

	func _init(_script_path: String, load_source_code := true) -> void:
		script_path = _script_path
		var f := FileAccess.open(_script_path, FileAccess.READ)
		var err := f.get_open_error()
		assert(err == OK, "Unable to open %s for reading" % [_script_path])
		source_code = f.get_as_text()
		f.close()

	func coverage_count() -> int:
		process_queue()
		var count := 0
		for line in coverage_lines:
			if coverage_lines[line] > 0:
				count += 1
		return count

	func coverage_line_count() -> int:
		process_queue()
		return len(coverage_lines)

	func coverage_percent() -> float:
		process_queue()
		var clc = coverage_line_count()
		return (float(coverage_count()) / float(clc)) * 100.0 if clc > 0 else 100.0

	func add_line_coverage(line_number: int, count := 1) -> void:
		if !line_number in coverage_lines:
			coverage_lines[line_number] = 0
		coverage_lines[line_number] = coverage_lines[line_number] + count

	func get_coverage_json() -> Dictionary:
		process_queue()
		return coverage_lines.duplicate()

	func merge_coverage_json(coverage_json: Dictionary) -> void:
		for line_number in coverage_json:
			add_line_coverage(int(line_number), coverage_json[line_number])

	func script_coverage(verbosity := Verbosity.None, target: float = INF):
		var result := PackedStringArray()
		var i = 0
		var coverage_percent := coverage_percent()
		var partial_show: bool = verbosity == Verbosity.PartialFiles && coverage_percent < 100 && coverage_percent > 0
		var failed_show: bool = verbosity == Verbosity.FailingFiles && coverage_percent < target
		var show_source = partial_show || failed_show || verbosity == Verbosity.AllFiles
		var pass_fail := ""
		if target != INF:
			pass_fail = "(fail) " if coverage_percent < target else "(pass) "
		result.append("%s%.1f%% %s" % [pass_fail, coverage_percent, script_path])
		if show_source:
			for line in source_code.split("\n"):
				result.append("%4d %s %s" % [
					i, "%4dx" % [coverage_lines[i]] if i in coverage_lines else "     ", line
				])
				i += 1
		return "\n".join(result)

	# virtual
	# Call this function to revert the script object to it's original state.
	func revert():
		pass

	# only process the queue if it got too big
	func maybe_process_queue():
		if len(coverage_queue) > MAX_QUEUE_SIZE:
			process_queue()

	func process_queue():
		for line in coverage_queue:
			add_line_coverage(line)
		coverage_queue = []

class ScriptCoverageCollector:
	extends ScriptCoverage

	# 1: print script names
	# 2: also print instrumented script code
	# 3: also print original script code
	const DEBUG_SCRIPT_COVERAGE := 2
	const DEBUG_SCRIPT_COVERAGE_DEPTH := false
	const ERR_MAP := {
		43: "PARSE_ERROR"
	}

	static var _last_script_id = 0
	var instrumented_source_code := ""
	var covered_script: Script

	class Indent:
		extends RefCounted
		enum State {None, Class, Func, StaticFunc, Match, MatchPattern}

		var depth: int
		var state: int
		var subclass_name: String

		func _init(_depth: int, _state: int, _subclass_name: String):
			depth = _depth
			state = _state
			subclass_name = _subclass_name

	func _init(coverage_script_path: String, _script_path: String) -> void:
		super(_script_path, false)
		var id = _last_script_id + 1
		_last_script_id = id
		covered_script = load(_script_path)
		source_code = covered_script.source_code
		if DEBUG_SCRIPT_COVERAGE:
			print(_script_path)
			if DEBUG_SCRIPT_COVERAGE > 2:
				_print_with_line_numbers(source_code)
		instrumented_source_code = _interpolate_coverage(coverage_script_path, covered_script, id)
		if DEBUG_SCRIPT_COVERAGE > 1:
			_print_with_line_numbers(instrumented_source_code)
		set_instrumented()

	func _set_script_code(new_source_code) -> void:
		if covered_script.source_code == new_source_code:
			return
		covered_script.source_code = new_source_code
		# if we pass 'keep_state = true' to reload() then we can reload the script
		# without removing it from all the nodes.
		# this requires us to add a function call for each line that checks to make
		# sure the coverage variable is set before calling add_line_coverage
		var err = covered_script.reload(true)

		assert(err == OK, "Error reloading %s: error: %s\n-------\n%s" % [
			covered_script.resource_path,
			ERR_MAP[err] if err in ERR_MAP else err,
			_add_line_numbers(covered_script.source_code)
		])

	func _print_with_line_numbers(source_code: String):
		print(_add_line_numbers(source_code))

	func set_instrumented(value := true):
		_set_script_code(instrumented_source_code if value else source_code)

	func revert():
		set_instrumented(false)

	func _add_line_numbers(source_code: String) -> String:
		var result := PackedStringArray()
		var i := 0
		for line in source_code.split("\n"):
			result.append("%4d: %s" % [i, line])
			i += 1
		return "\n".join(result)

	func _to_string():
		return script_coverage(2)

	func _get_token(stripped_line: String, skip := 0) -> String:
		var space_token = stripped_line.get_slice(" ", skip)
		var tab_token = stripped_line.get_slice("\t", skip)
		return space_token if space_token && len(space_token) < len(tab_token) else tab_token

	func _update_block_count(block_dict: Dictionary, line: String) -> void:
		for key in block_dict:
			var block_count = line.count(key[0]) - line.count(key[1])
			block_dict[key] += block_count

	func _count_block(block_dict: Dictionary) -> int:
		var result := 0
		for key in block_dict:
			result += block_dict[key]
		return result

	func _get_leading_whitespace(line: String) -> String:
		var leading_whitespace := PackedStringArray()
		for chr in range(len(line)):
			if line[chr] in [" ", "\t"]:
				leading_whitespace.append(line[chr])
			else:
				break
		return "".join(leading_whitespace)

	func _get_coverage_collector_expr(coverage_script_path: String, script_resource_path: String) -> String:
		return "load(\"%s\").get_instance().get_coverage_collector(\"%s\")" % [
				coverage_script_path,
				script_resource_path
			]

	func _interpolate_coverage(coverage_script_path: String, script: GDScript, id: int) -> String:
		var collector_var := "__cl__"
		var lines = script.source_code.split("\n")
		var indent_stack := []
		var ld_stack := []
		var write_var := false
		var state:int = Indent.State.None
		var next_state: int = Indent.State.None
		var subclass_name: String
		var next_subclass_name: String
		var depth := 0
		var out_lines := PackedStringArray()
		# 0 based, start with -1 so that the first increment will give 0
		var i := -1
		var block := {
			'{}': 0,
			'()': 0,
			'[]': 0
		}
		# the collector var must be placed after 'extends' b
		var continuation := false

		for line_ in lines:
			i += 1
			var line := line_ as String
			var stripped_line := line.strip_edges()
			if stripped_line == "" || stripped_line.begins_with("#"):
				out_lines.append(line)
				continue
			# if we are inside a block then block_count will be > 0, we can't insert instrumentation
			var block_count := _count_block(block)
			# update the block count ( '(', '{' and '[' characters create a block )
			_update_block_count(block, stripped_line)
			# if we are in a block or have a continuation from the last line
			# don't add instrumentation
			var skip := block_count > 0 || continuation
			continuation = stripped_line.ends_with('\\')
			if skip:
				out_lines.append(line)
				continue

			var leading_whitespace := _get_leading_whitespace(line)
			var line_depth = len(leading_whitespace)
			while line_depth < depth:
				var indent = indent_stack.pop_back()
				if DEBUG_SCRIPT_COVERAGE_DEPTH:
					print("\t\t\t\tPOP_LINE_DEPTH %s > %s (%s) %s  (was %s) %s" % [depth, indent.depth, state, indent.subclass_name, subclass_name, subclass_name && subclass_name != indent.subclass_name])
				depth = indent.depth
				state = indent.state
				next_state = indent.state
				subclass_name = indent.subclass_name
			if line_depth > depth:
				if DEBUG_SCRIPT_COVERAGE_DEPTH:
					print("\t\t\t\tPUSH_LINE_DEPTH %s > %s (%s > %s) %s" % [depth, line_depth, state, next_state, subclass_name])
				indent_stack.append(Indent.new(depth, state, subclass_name))
				if next_subclass_name:
					subclass_name = next_subclass_name
				next_subclass_name = ''
				state = next_state
			depth = line_depth

			var first_token := _get_token(stripped_line)
			match first_token:
				"func":
					next_state = Indent.State.Func
					write_var = true
				"class":
					next_state = Indent.State.Class
					next_subclass_name = _get_token(stripped_line, 1).trim_suffix(":")
				"static":
					write_var = true
					next_state = Indent.State.StaticFunc
				"else:", "elif":
					skip = true
				"match":
					next_state = Indent.State.Match
			if state == Indent.State.Match:
				next_state = Indent.State.MatchPattern
			elif state == Indent.State.MatchPattern:
				next_state = Indent.State.Func
			if !skip && state in [Indent.State.Func, Indent.State.StaticFunc]:
				if write_var:
					write_var = false
					out_lines.append("%svar %s = %s.coverage_queue" % [
						leading_whitespace,
						collector_var,
						_get_coverage_collector_expr(coverage_script_path, script.resource_path)
					])
				coverage_lines[i] = 0
				out_lines.append("%s%s.append(%s)" % [
					leading_whitespace,
					collector_var,
					i
				])
			out_lines.append(line)
		return "\n".join(out_lines)

# this is a placeholder class for when we've finalized and don't want coverage anymore
# some scripts will continue to be instrumented so we must have something to accept all these calls
class NullCoverage:
	extends RefCounted
	func get_coverage_collector(_script_name: String):
		return self

	func add_line_coverage(_line: int):
		pass

static var _instance = null
var coverage_collectors := {}
var _scene_tree: MainLoop
var _exclude_paths := []
var _enforce_node_coverage := false
var _autoloads_instrumented := false
var _coverage_target_file := INF
var _coverage_target_total := INF

func _init(scene_tree: MainLoop, exclude_paths := []):
	_exclude_paths += exclude_paths
	assert(!_instance, "Only one instance of this class is allowed")
	_instance = self
	_scene_tree = scene_tree

func enforce_node_coverage():
	var err := _scene_tree.connect("tree_changed", Callable(self, "_on_tree_changed"))
	assert(err == OK)
	_enforce_node_coverage = true
	# this may error on autoload if you don"t call `instrument_autoloads()` immediately
	_on_tree_changed()
	return self

func _finalize(print_verbosity := 0):
	for script_path in coverage_collectors:
		coverage_collectors[script_path].revert()
	if _enforce_node_coverage:
		_scene_tree.disconnect("tree_changed", Callable(self, "_on_tree_changed"))
	print(script_coverage(print_verbosity))

func get_coverage_collector(script_name: String):
	var result = coverage_collectors[script_name] if script_name in coverage_collectors else null
	if result:
		result.maybe_process_queue()
	return result

func coverage_count() -> int:
	var result := 0
	for script in coverage_collectors:
		result += coverage_collectors[script].coverage_count()
	return result

func coverage_line_count() -> int:
	var result := 0
	for script in coverage_collectors:
		result += coverage_collectors[script].coverage_line_count()
	return result

func coverage_percent() -> float:
	var clc = coverage_line_count()
	return (float(coverage_count()) / float(clc)) * 100.0 if clc > 0 else 100.0

func set_coverage_targets(total: float, file: float) -> void:
	_coverage_target_total = total
	_coverage_target_file = file

func coverage_passing() -> bool:
	var all_files_passing := true
	if _coverage_target_file < INF:
		for script in coverage_collectors:
			var script_percent = coverage_collectors[script].coverage_percent()
			all_files_passing = all_files_passing && script_percent > _coverage_target_file
	return coverage_percent() > _coverage_target_total && all_files_passing

# see ScriptCoverage.Verbosity for verbosity levels
func script_coverage(verbosity := 0):
	var result = PackedStringArray()
	var coverage_count := 0
	var coverage_lines := 0
	var coverage_percent := coverage_percent()
	var pass_fail := ""
	if _coverage_target_total != INF:
		pass_fail = "(fail) " if coverage_percent < _coverage_target_total else "(pass) "
	var multiline := false
	if verbosity > Verbosity.None:
		for script in coverage_collectors:
			var file_coverage = coverage_collectors[script].script_coverage(verbosity, _coverage_target_file)
			result.append("%s" % [file_coverage])
			if file_coverage.match("*\n*"):
				multiline = true
	result.append("%s%.1f%% Total Coverage: %s/%s lines" % [
		pass_fail,
		coverage_percent,
		coverage_count(),
		coverage_line_count()
	])

	return "\n\n" if multiline else "\n".join(result)

func merge_from_coverage_file(filename: String, auto_instrument := true) -> bool:
	var f := FileAccess.open(filename, FileAccess.READ)
	var err := f.get_open_error()
	if err != OK:
		printerr("Error %s opening %s for reading" % [err, filename])
		return false
	var test_json_conv = JSON.new()
	test_json_conv.parse(f.get_as_text());
	var parsed = test_json_conv.get_data()
	f.close()
	if parsed.error != OK:
		printerr("Error %s on line %s parsing %s" % [parsed.error, parsed.error_line, filename])
		printerr(parsed.error_string)
		return false
	if !parsed.result is Dictionary:
		printerr("Error: content of %s expected to be a dictionary" % [filename])
		return false
	for script_path in parsed.result:
		if !parsed.result[script_path] is Dictionary:
			printerr("Error: %s in %s is expected to be a dictionary" % [
				script_path, filename
			])
			return false
		if auto_instrument:
			_instrument_script(load(script_path))
		elif !script_path in coverage_collectors:
			coverage_collectors[script_path] = ScriptCoverage.new(script_path)
		coverage_collectors[script_path].merge_coverage_json(parsed.result[script_path])
	return true

func save_coverage_file(filename: String) -> bool:
	var coverage := {}
	for script_path in coverage_collectors:
		coverage[script_path] = coverage_collectors[script_path].get_coverage_json()
	var f := FileAccess.open(filename, FileAccess.WRITE)
	var err := f.get_open_error()
	if err != OK:
		printerr("Error %s opening %s for writing" % [err, filename])
		return false
	f.store_string(JSON.stringify(coverage))
	f.close()
	return true

func _on_tree_changed():
	_ensure_node_script_instrumentation(_scene_tree.root)

func _excluded(resource_path: String) -> bool:
	var excluded = false
	for ep in _exclude_paths:
		if resource_path.match(ep):
			excluded = true
			break
	return excluded

func _ensure_node_script_instrumentation(node: Node):
	# this is too late, if a node already has the script then reload it fails with ERR_ALREADY_IN_USE
	var script = node.get_script()
	if script is GDScript:
		assert(_excluded(script.resource_path) || script.resource_path in coverage_collectors, "Node %s has a non-instrumented script %s" % [
			node.get_path() if node.is_inside_tree() else node.name,
			script.resource_path
		])
	for n in node.get_children():
		_ensure_node_script_instrumentation(n)

func _instrument_script(script: GDScript) -> void:
	var script_path = script.resource_path
	var coverage_script_path = get_script().resource_path
	if !script_path:
		printerr("script has no path: %s" % [script.source_code])

	if !_excluded(script_path) && script_path && !script_path in coverage_collectors:
		coverage_collectors[script_path] = ScriptCoverageCollector.new(coverage_script_path ,script_path)
		# BROKEN! https://github.com/godotengine/godot/issues/83590
		var deps = ResourceLoader.get_dependencies(script_path)
		for dep in deps:
			if dep.get_extension() == "gd":
				_instrument_script(load(dep))

func instrument_scene_scripts(scene: PackedScene):
	var s := scene.get_state()
	for i in range(s.get_node_count()):
		var node_instance = s.get_node_instance(i)
		if node_instance:
			# load this packed scene and replace all scripts etc
			print('instrument_script %s ' % [node_instance])
			instrument_scene_scripts(node_instance)
		for npi in range(s.get_node_property_count(i)):
			var p = s.get_node_property_name(i, npi)
			if p == "script":
				_instrument_script(s.get_node_property_value(i, npi))
	return self

func _collect_script_objects(obj: Object, objs: Array, obj_set: Dictionary):
	# prevent cycles
	obj_set[obj] = true
	assert(obj && obj.get_script(), "Couldn't collect script from %s" % [obj])
	if obj.get_script() && !_excluded(obj.get_script().resource_path):
		objs.append({
			obj = obj,
			script = obj.get_script()
		})
	# collect all child nodes of an autoload that may have scripts attached
	if obj is Node:
		for c in obj.get_children():
			var script = c.get_script()
			if script && script.resource_path:
				_collect_script_objects(c, objs, obj_set)
	# collect all properties of autoloaded objects that may have scripts attached
	for p in obj.get_property_list():
		if p.type == TYPE_OBJECT:
			if p.name in obj:
				var value = obj.get(p.name)
				if !value in obj_set:
					var script = value.get_script() if value else null
					if script && script.resource_path:
						_collect_script_objects(value, objs, obj_set)

func _collect_autoloads():
	assert(!_autoloads_instrumented, "Tried to collect autoloads twice?")
	_autoloads_instrumented = true
	var autoloaded := []
	var obj_set := {}
	assert(_scene_tree is SceneTree, "Cannot collect autoloads from %s because it is not a SceneTree" % [ _scene_tree ])
	var root := (_scene_tree as SceneTree).root
	for n in root.get_children():
		var setting_name = "autoload/%s" % [n.name]
		var autoload_setting = ProjectSettings.get_setting(setting_name) if ProjectSettings.has_setting(setting_name) else ""
		if autoload_setting:
			_collect_script_objects(n, autoloaded, obj_set)
	autoloaded.reverse()
	var deps := []
	for item in autoloaded:
		for d in ResourceLoader.get_dependencies(item.script.resource_path):
			var dep_script = load(d)
			if dep_script:
				deps.append({obj = null, script = dep_script})
	return deps + autoloaded

func instrument_autoloads(script_list: Array = []):
	var autoload_scripts = _collect_autoloads()
	autoload_scripts.reverse()
	for item in autoload_scripts:
		_instrument_script(item.script)
	return self

func instrument_scripts(path: String):
	var list := _list_scripts_recursive(path)
	for script in list:
		_instrument_script(load(script))
	return self

func _list_scripts_recursive(path: String, list := []) -> Array:
	var d := DirAccess.open(path)
	var err := d.get_open_error()
	assert(err == OK, "Error opening path %s: %s" % [path, err])
	err = d.list_dir_begin() # TODOConverter3To4 fill missing arguments https://github.com/godotengine/godot/pull/40547
	assert(err == OK, "Error listing directory %s: %s" % [path, err])
	var next := d.get_next()
	while next:
		var next_path = path.path_join(next)
		if next.get_extension() == "gd":
			if !_excluded(next_path):
				list.append(next_path)
		elif d.dir_exists(next_path):
			_list_scripts_recursive(next_path, list)
		next = d.get_next()
	d.list_dir_end()
	return list

static func get_instance(strict := true):
	# unable to reference the Coverage script from a static so you need to call Coverage.new(...) first
	assert(!strict || _instance, "No instance has been created, use Coverage.new(get_tree()) first.")
	return _instance

static func finalize(print_verbosity := 0) -> void:
	_instance._finalize(print_verbosity)
	_instance = NullCoverage.new()
