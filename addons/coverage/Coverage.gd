extends Reference

class ScriptCoverageCollector:
	extends Reference

	const DEBUG_SCRIPT_COVERAGE := false
	const STATIC_VARS := {last_script_id = 0}
	const ERR_MAP := {
		43: "PARSE_ERROR"
	}


	var coverage_lines := {}
	var script_path := ""
	var source_code := ""
	var covered_script: Script
	var _collector_var_name := ""

	class Indent:
		extends Reference
		enum State {None, Class, Func, StaticFunc, Match, MatchPattern}

		var depth: int
		var state: int
		var subclass_name: String

		func _init(_depth: int, _state: int, _subclass_name: String):
			depth = _depth
			state = _state
			subclass_name = _subclass_name


	func _init(coverage_script_path: String, _script_path: String) -> void:
		script_path = _script_path
		var script = load(_script_path)
		if DEBUG_SCRIPT_COVERAGE:
			print(script)
		covered_script = script
		source_code = script.source_code
		var id = STATIC_VARS.last_script_id + 1
		STATIC_VARS.last_script_id = id
		script.source_code = _interpolate_coverage(coverage_script_path, script, id)
		if DEBUG_SCRIPT_COVERAGE:
			print(script.source_code)
		# if we pass 'keep_state = true' to reload() then we can reload the script
		# without removing it from all the nodes.
		# this requires us to add a function call for each line that checks to make
		# sure the coverage variable is set before calling add_line_coverage
		var err = script.reload(true)

		assert(err == OK, "Error reloading %s: error: %s\n-------\n%s" % [
			script.resource_path,
			ERR_MAP[err] if err in ERR_MAP else err,
			_add_line_numbers(script.source_code)
		])
		if DEBUG_SCRIPT_COVERAGE:
			print("new script resource_path %s" % [covered_script.resource_path])

	func _add_line_numbers(source_code: String) -> String:
		var result := PoolStringArray()
		var i := 0
		for line in source_code.split("\n"):
			result.append("%4d: %s" % [i, line])
			i += 1
		return result.join("\n")

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

	func _find_next_extends(i: int, lines: Array) -> int:
		var last_whitespace = _get_leading_whitespace(lines[i])
		var result := i
		while i < len(lines):
			var stripped_line = lines[i].strip_edges()
			var leading_whitespace = _get_leading_whitespace(lines[i])
			var first_token = _get_token(stripped_line)
			if first_token == 'class_name':
				first_token = _get_token(stripped_line, 2)
			if first_token == 'extends':
				return i + 1
			# 	if (!p_class->constant_expressions.empty() || !p_class->subclasses.empty() || !p_class->functions.empty() || !p_class->variables.empty())
			if last_whitespace != leading_whitespace || first_token && first_token in ['const', 'class', 'func', 'var', 'onready', 'export']:
				break
			i += 1
		# if we make it here then there is an implicit 'extends Object' and we don't need to worry
		return result

	func _get_leading_whitespace(line: String) -> String:
		var leading_whitespace := PoolStringArray()
		for chr in range(len(line)):
			if line[chr] in [" ", "\t"]:
				leading_whitespace.append(line[chr])
			else:
				break
		return leading_whitespace.join("")

	func _get_coverage_collector_expr(coverage_script_path: String, script_resource_path: String) -> String:
		return "load(\"%s\").instance().get_coverage_collector(\"%s\")" % [
				coverage_script_path,
				script_resource_path
			]

	func _collector_var_name(subclass_name: String) -> String:
		return "%s_%s__" % [_collector_var_name, subclass_name]

	func _collector_var(leading_whitespace: String, subclass_name: String, coverage_script_path: String, script_resource_path: String) -> String:
		var var_name = _collector_var_name(subclass_name)
		return "\n" + leading_whitespace + PoolStringArray([
			"var %s" % [var_name],
			"func %s(line):" % [var_name],
			"\tif !%s:" % [var_name],
			"\t\t%s = %s" % [var_name, _get_coverage_collector_expr(coverage_script_path, script_resource_path)],
			"\t%s.add_line_coverage(line)" % [var_name]
		]).join('\n%s' % [leading_whitespace])

	func _interpolate_coverage(coverage_script_path: String, script: GDScript, id: int) -> String:
		var lines = script.source_code.split("\n")
		var indent_stack := []
		var ld_stack := []
		var state:int = Indent.State.None
		var next_state: int = Indent.State.None
		var subclass_name: String
		var next_subclass_name: String
		var depth := 0
		var out_lines := PoolStringArray()
		# 0 based, start with -1 so that the first increment will give 0
		var i := -1
		var block := {
			'{}': 0,
			'()': 0,
			'[]': 0
		}
		# the collector var must be placed after 'extends' but
		# should be skipped if the source code un-indents before it's added
		var collector_var_line := _find_next_extends(0, lines)
		var collector_var_depth := -1
		var add_collector_var := false
		var continuation := false
		_collector_var_name = "__script_coverage_collector%s" % [id]


		for line_ in lines:
			i += 1
			var line := line_ as String
			var leading_whitespace := _get_leading_whitespace(line)
			var line_depth = len(leading_whitespace)
			var stripped_line := line.strip_edges()
			if stripped_line == "" || stripped_line.begins_with("#"):
				out_lines.append(line)
				continue
			if collector_var_line >= 0 && collector_var_line <= i:
				# don't add the collector var if we aren't at the same depth
				# e.g. Reference class where `extends` is the only line
				if collector_var_depth < line_depth:
					var s = get_script()
					out_lines.append("%s%s" % [
						leading_whitespace,
						_collector_var(leading_whitespace, subclass_name, coverage_script_path, script.resource_path)
					])
				collector_var_line = -1

			while line_depth < depth:
				var indent = indent_stack.pop_back()
				depth = indent.depth
				state = indent.state
				subclass_name = indent.subclass_name
				if DEBUG_SCRIPT_COVERAGE:
					print("POP_LINE_DEPTH %s > %s (%s) %s  (was %s)" % [depth, indent.depth, state, indent.subclass_name, subclass_name])
			if line_depth > depth:
				if DEBUG_SCRIPT_COVERAGE:
					print("PUSH_LINE_DEPTH %s > %s (%s > %s) %s" % [depth, line_depth, state, next_state, subclass_name])
				indent_stack.append(Indent.new(depth, state, subclass_name))
				if next_subclass_name:
					subclass_name = next_subclass_name
				next_subclass_name = ''
				state = next_state
			depth = line_depth
			var first_token := _get_token(stripped_line)
			# if we are inside a block then block_count will be > 0, we can't insert instrumentation
			var block_count := _count_block(block)
			# update the block count ( '(', '{' and '[' characters create a block )
			_update_block_count(block, stripped_line)
			# if we are in a block or have a continuation from the last line or start with # (comment)
			# don't add instrumentation

			var skip := block_count > 0 || continuation
			continuation = stripped_line.ends_with('\\')

			match first_token:
				"func":
					next_state = Indent.State.Func
				"class":
					next_state = Indent.State.Class
					collector_var_line = _find_next_extends(i + 1, lines)
					collector_var_depth = depth
					next_subclass_name = _get_token(stripped_line, 1).trim_suffix(":")
				"static":
					next_state = Indent.State.StaticFunc
				"else:", "elif":
					skip = true
				"match":
					next_state = Indent.State.Match
			if state == Indent.State.Match && stripped_line.ends_with(":"):
				next_state = Indent.State.MatchPattern
			elif state == Indent.State.MatchPattern:
				next_state = Indent.State.Func
			if !skip && state in [Indent.State.Func, Indent.State.StaticFunc]:
				var fn_call = _collector_var_name(subclass_name)
				if state == Indent.State.StaticFunc:
					fn_call = "%s.add_line_coverage" % [
						_get_coverage_collector_expr(coverage_script_path, script.resource_path)
					]
				coverage_lines[i] = 0
				out_lines.append("%s%s(%s)" % [
					leading_whitespace,
					fn_call,
					i
				])
			out_lines.append(line)
		return out_lines.join("\n")

const STATIC_VARS := {instance=null}
var coverage_collectors := {}
var _scene_tree: SceneTree
var _exclude_paths := []
var _enforce_node_coverage := false
var _autoloads_instrumented := false

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
	var root := _scene_tree.root
	for n in root.get_children():
		var setting_name = "autoload/%s" % [n.name]
		var autoload_setting = ProjectSettings.get_setting(setting_name) if ProjectSettings.has_setting(setting_name) else ""
		if autoload_setting:
			_collect_script_objects(n, autoloaded, obj_set)
	autoloaded.invert()
	var deps := []
	for item in autoloaded:
		for d in ResourceLoader.get_dependencies(item.script.resource_path):
			var dep_script = load(d)
			if dep_script:
				deps.append({obj = null, script = dep_script})
	return deps + autoloaded

func instrument_autoloads(script_list: Array = []):
	var autoload_scripts = _collect_autoloads()
	autoload_scripts.invert()
	for item in autoload_scripts:
		_instrument_script(item.script)
	return self

func instrument_scripts(path: String):
	var list := _list_scripts_recursive(path)
	for script in list:
		_instrument_script(load(script))
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
			if !_excluded(next_path):
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
