extends Reference

class ScriptCoverageCollector:
	extends Reference

	const DEBUG_SCRIPT_COVERAGE := false

	enum State {None, Class, Func, StaticFunc}
	var coverage_lines := {}
	var script_path := ""
	var source_code := ""
	var covered_script: Script

	func _init(coverage_script_path: String, _script_path: String) -> void:
		script_path = _script_path
		var script = load(_script_path)
		if DEBUG_SCRIPT_COVERAGE:
			print(script)
		covered_script = script
		source_code = script.source_code
		script.source_code = _interpolate_coverage(coverage_script_path, script)
		if DEBUG_SCRIPT_COVERAGE:
			print(script.source_code)
		var err = script.reload()
		assert(err == OK, "Error reloading %s: %s\n%s" % [
			script.resource_path,
			err,
			script.source_code
		])
		if DEBUG_SCRIPT_COVERAGE:
			print("new script resource_path %s" % [covered_script.resource_path])

	func _to_string():
		var result := PoolStringArray()
		var i = 0
		for line in source_code.split("\n"):
			result.append("%4d %s %s" % [
				i, "%4dx" % [coverage_lines[i]] if i in coverage_lines else "     ", line
			])
			i += 1
		result.append("%.1f%%" % [coverage_percent()])
		return result.join("\n")

	func coverage_count() -> int:
		var count = 0
		for line in coverage_lines:
			if coverage_lines[line] > 0:
				count += 1
		return count

	func coverage_line_count() -> int:
		return len(coverage_lines)

	func coverage_percent() -> float:
		var clc = coverage_line_count()
		return (float(coverage_count()) / float(clc)) * 100.0 if clc > 0 else NAN

	func add_line_coverage(line_number) -> void:
		if !line_number in coverage_lines:
			coverage_lines[line_number] = 0
		coverage_lines[line_number] = coverage_lines[line_number] + 1

	func _get_first_token(stripped_line: String) -> String:
		var space_token = stripped_line.get_slice(" ", 0)
		var tab_token = stripped_line.get_slice("\t", 0)
		return space_token if len(space_token) < len(tab_token) else tab_token

	func _update_block_count(block_dict: Dictionary, line: String) -> void:
		for key in block_dict:
			var block_count = line.count(key[0]) - line.count(key[1])
			block_dict[key] += block_count

	func _count_block(block_dict: Dictionary) -> int:
		var result := 0
		for key in block_dict:
			result += block_dict[key]
		return result

	func _interpolate_coverage(coverage_script_path: String, script: GDScript) -> String:
		var lines = script.source_code.split("\n")
		var state_stack := []
		var ld_stack := []
		var state:int = State.None
		var next_state: int = State.None
		var depth := 0
		var out_lines := PoolStringArray()
		var i := -1
		var block := {
			'{}': 0,
			'()': 0,
			'[]': 0
		}
		var add_collector_var := false
		var continuation := false
		var NOT_IN_MATCH := 0xEFFFFFFF
		var in_match := NOT_IN_MATCH
		var collector_var := "var __script_coverage_collector__ = preload(\"%s\").instance().get_coverage_collector(\"%s\")" % [
			coverage_script_path,
			script.resource_path
		]
		for line_ in lines:
			i += 1
			if i == 1:
				var s = get_script()
				# todo: figure out how to get this path
				out_lines.append(collector_var)
			var line := line_ as String
			var stripped_line := line.strip_edges()
			if stripped_line == "":
				out_lines.append(line)
				continue
			var line_depth = 0
			var leading_whitespace := PoolStringArray()
			for chr in range(len(line)):
				if line[chr] in [" ", "\t"]:
					line_depth += 1
					leading_whitespace.append(line[chr])
				else:
					break
			while line_depth < depth:
				depth = ld_stack.pop_back()
				state = state_stack.pop_back()
				if DEBUG_SCRIPT_COVERAGE:
					print("POP_LINE_DEPTH %s %s" % [depth, state])
				if depth < in_match:
					in_match = NOT_IN_MATCH
			if line_depth > depth:
				state_stack.append(state)
				ld_stack.append(depth)
				state = next_state
			depth = line_depth
			var first_token := _get_first_token(stripped_line)
			# if we are inside a block then block_count will be > 0, we can't insert instrumentation
			var block_count := _count_block(block)
			# update the block count ( '(', '{' and '[' characters create a block )
			_update_block_count(block, stripped_line)
			# if we are in a block or have a continuation from the last line, don't add instrumentation
			var skip := block_count > 0 || continuation
			continuation = stripped_line.ends_with('\\')

			if add_collector_var && first_token != "extends":
				out_lines.append("%s%s" % [
					leading_whitespace.join(""),
					collector_var
				])
				add_collector_var = false
			match first_token:
				"func":
					next_state = State.Func
				"class":
					next_state = State.Class
					add_collector_var = true
				"static":
					next_state = State.StaticFunc
				"else:", "elif":
					skip = true
				"match":
					# lazy code here, could be improved to actually deal with nested matches properly
					if in_match == NOT_IN_MATCH:
						in_match = depth
			if in_match && stripped_line.ends_with(':'):
				skip = true

			if state == State.Func && !skip:
				coverage_lines[i] = 0
				out_lines.append("%s__script_coverage_collector__.add_line_coverage(%s)" % [
					leading_whitespace.join(""),
					i
				])
			out_lines.append(line)
		return out_lines.join("\n")

const STATIC_VARS := {instance=null}
var coverage_collectors := {}
var _scene_tree: SceneTree
var _exclude_paths := []
var _enforce_node_coverage := false

func _init(scene_tree: SceneTree, exclude_paths := []):
	_exclude_paths += exclude_paths
	assert(!STATIC_VARS.instance, "Only one instance of this class is allowed")
	STATIC_VARS.instance = self
	_scene_tree = scene_tree

func enforce_node_coverage():
	var err := _scene_tree.connect("tree_changed", self, "_on_tree_changed")
	assert(err == OK)
	_enforce_node_coverage = true
	# this may error on autoload if you don"t call `instrument_autoloads()` immediately
	_on_tree_changed()
	return self

func _finalize(print_verbose := false):
	if _enforce_node_coverage:
		_scene_tree.disconnect("tree_changed", self, "_on_tree_changed")
	print(script_coverage(print_verbose))

func get_coverage_collector(script_name: String):
	return coverage_collectors[script_name] if script_name in coverage_collectors else null

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
	return (float(coverage_count()) / float(clc)) * 100.0 if clc > 0 else NAN

func script_coverage(verbose := false):
	var result = PoolStringArray()
	var coverage_count := 0
	var coverage_lines := 0
	if verbose:
		for script in coverage_collectors:
			result.append("%s:" % [script])
			result.append("%s" % [coverage_collectors[script]])
	result.append("Coverage: %s/%s %.1f%%" % [
		coverage_count(),
		coverage_line_count(),
		coverage_percent()
	])

	return result.join("\n\n")

func _on_tree_changed():
	_ensure_node_script_instrumentation(_scene_tree.root)

func _ensure_node_script_instrumentation(node: Node):
	# this is too late, if a node already has the script then reload it fails with ERR_ALREADY_IN_USE
	var script = node.get_script()
	if script is GDScript:
		var excluded = false
		for ep in _exclude_paths:
			if script.resource_path.match(ep):
				excluded = true
				break
		assert(excluded || script.resource_path in coverage_collectors, "Node %s has a non-instrumented script %s" % [
			node.get_path() if node.is_inside_tree() else node.name,
			script.resource_path
		])
	for n in node.get_children():
		_ensure_node_script_instrumentation(n)

func _instrument_script(script: GDScript) -> GDScript:
	var script_path = script.resource_path
	var coverage_script_path = get_script().resource_path
	if !script_path:
		print("script has no path: %s" % [script.source_code])
	if script_path && !script_path in coverage_collectors:
		coverage_collectors[script_path] = ScriptCoverageCollector.new(coverage_script_path ,script_path)
		var deps = ResourceLoader.get_dependencies(script_path)
		for dep in deps:
			if dep.get_extension() == "gd":
				_instrument_script(load(dep))
	return coverage_collectors[script_path].covered_script

func instrument_scene_scripts(scene: PackedScene):
	var s := scene.get_state()
	for i in range(s.get_node_count()):
		var node_instance = s.get_node_instance(i)
		if node_instance:
			# load this packed scene and replace all scripts etc
			instrument_scene_scripts(node_instance)
		for npi in range(s.get_node_property_count(i)):
			var p = s.get_node_property_name(i, npi)
			if p == "script":
				_instrument_script(s.get_node_property_value(i, npi))
	return self

func _collect_script_objects(obj: Object, objs: Array, obj_set: Dictionary):
	# prevent cycles
	obj_set[obj] = true
	assert(obj)
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

func _collect_and_unload_autoloads():
	var autoloaded := []
	var obj_set := {}
	var root := _scene_tree.root
	for n in root.get_children():
		var setting_name = "autoload/%s" % [n.name]
		var autoload_setting = ProjectSettings.get_setting(setting_name) if ProjectSettings.has_setting(setting_name) else ""
		if autoload_setting:
			_collect_script_objects(n, autoloaded, obj_set)
	autoloaded.invert()
	for item in autoloaded:
		var obj = item.obj
		# since these are autoloaded they shouldn"t have signal connections except those
		# that are created in _init or _ready...
		for s in obj.get_signal_list():
			for cs in obj.get_signal_connection_list(s.name):
				obj.disconnect(s.name, cs.target, cs.method)

		item.obj.set_script(null)
	return autoloaded

func _reset_autoloads(autoload_scripts: Array):
	for item in autoload_scripts:
		item.obj.set_script(item.script)
		if item.obj.has_method("_ready"):
			item.obj._ready()

func instrument_autoloads():
	var autoload_scripts = _collect_and_unload_autoloads()
	autoload_scripts.invert()
	for item in autoload_scripts:
		_instrument_script(item.script)
	_reset_autoloads(autoload_scripts)
	return self

func instrument_scripts(path: String, instrument_autoloads := true):
	var autoload_scripts = _collect_and_unload_autoloads() if instrument_autoloads else []
	var list := _list_scripts_recursive(path)
	for script in list:
		_instrument_script(load(script))
	if instrument_autoloads:
		_reset_autoloads(autoload_scripts)
	return self

func _list_scripts_recursive(path: String, list := []) -> Array:
	var d := Directory.new()
	var err := d.open(path)
	assert(err == OK, "Error opening path %s: %s" % [path, err])
	err = d.list_dir_begin(true)
	assert(err == OK, "Error listing directory %s: %s" % [path, err])
	var next := d.get_next()
	while next:
		var next_path = path.plus_file(next)
		if next.get_extension() == "gd":
			var exclude := false
			for ep in _exclude_paths:
				if next_path.match(ep):
					exclude = true
					break
			if !exclude:
				list.append(next_path)
		elif d.dir_exists(next_path):
			_list_scripts_recursive(next_path, list)
		next = d.get_next()
	d.list_dir_end()
	return list

static func instance():
	# unable to reference the Coverage script from a static so you need to call Coverage.new(...) first
	assert(STATIC_VARS.instance, "No instance has been created, use Coverage.new(get_tree()) first.")
	return STATIC_VARS.instance

static func finalize(print_verbose := false) -> void:
	STATIC_VARS.instance._finalize(print_verbose)
	STATIC_VARS.instance = null
