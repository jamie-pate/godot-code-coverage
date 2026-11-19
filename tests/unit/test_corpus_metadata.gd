extends GutTest

# Validates the hand-derived expected.metadata.json goldens (#4) against
# Instrumentation Contract v1.4 (§3.1, §3.2, §4, §6, §7) and the Seed Corpus
# Specification. The tables below are restated by hand from the spec on
# purpose: executable_lines and skipped_lines are each checked against their
# own literal list, not only inferred from line_mappings.
#
# Scope (decided on #4, reading (b)): line_mappings carry original_line,
# classification and hit_record_inserted only. instrumented_lines is not
# predicted here; it is fixed by expected.instrumented.gd (#28) once #17
# settles class-level injection.

const CORPUS_DIR = "res://tests/corpus"
const SPEC_DIR = "res://docs"
const SPEC_PREFIX = "seed-corpus-specification-v"
const GOLDEN = "expected.metadata.json"
const CONTRACT_VERSION = "1.5"

const TOP_LEVEL_KEYS = [
	"contract_version", "line_mappings", "executable_lines", "skipped_lines", "functions"
]
const MAPPING_KEYS = ["original_line", "classification", "hit_record_inserted"]
const FUNCTION_KEYS = ["name", "start_line", "end_line", "class_scope", "is_static"]
const CLASS_NAMES = {"E": "executable", "N": "non_executable", "S": "structural"}

# Seed Corpus Specification default configuration (Contract v1.4 §13.3).
const CORPUS_DEFAULTS = {
	"enable_instrumentation": true,
	"include_non_executable": true,
	"emit_function_metadata": true,
	"hit_recorder_expression": "__coverage_hit({line})",
}

const SUCCESS_ENTRIES = [
	"basic_statements",
	"control_flow",
	"multiline",
	"lambdas",
	"static_init",
	"typed_annotations",
	"class_level",
	"autoload_style",
	"await_coroutines",
	"disabled_instrumentation",
]

# Entries whose spec section points at another entry's source and metadata.
const COPY_OF = {"disabled_instrumentation": "basic_statements"}

# One character per original line: E executable, N non_executable, S structural.
const CLASS_MAP = {
	"basic_statements": "NSNNENSEEE",
	"control_flow": "SNSSESESE",
	"multiline": "SNSESE",
	"lambdas": "SNSSEEE",
	"static_init": "SNENSENSE",
	"typed_annotations": "SNENSE",
	"class_level": "SNSENSENSE",
	"autoload_style": "SNENSE",
	"await_coroutines": "SNSEE",
	"disabled_instrumentation": "NSNNENSEEE",
}

const EXECUTABLE = {
	"basic_statements": [5, 8, 9, 10],
	"control_flow": [5, 7, 9],
	"multiline": [4, 6],
	"lambdas": [5, 6, 7],
	"static_init": [3, 6, 9],
	"typed_annotations": [3, 6],
	"class_level": [4, 7, 10],
	"autoload_style": [3, 6],
	"await_coroutines": [4, 5],
	"disabled_instrumentation": [5, 8, 9, 10],
}

const SKIPPED = {
	"basic_statements": [1, 2, 3, 4, 6, 7],
	"control_flow": [1, 2, 3, 4, 6, 8],
	"multiline": [1, 2, 3, 5],
	"lambdas": [1, 2, 3, 4],
	"static_init": [1, 2, 4, 5, 7, 8],
	"typed_annotations": [1, 2, 4, 5],
	"class_level": [1, 2, 3, 5, 6, 8, 9],
	"autoload_style": [1, 2, 4, 5],
	"await_coroutines": [1, 2, 3],
	"disabled_instrumentation": [1, 2, 3, 4, 6, 7],
}


func test_golden_exists_and_parses(entry = use_parameters(SUCCESS_ENTRIES)) -> void:
	var path = _path(entry, GOLDEN)
	assert_true(FileAccess.file_exists(path), path + " is missing")
	assert_false(_golden(entry).is_empty(), path + " is not a JSON object")


func test_golden_uses_lf_and_one_trailing_newline(entry = use_parameters(SUCCESS_ENTRIES)) -> void:
	var text = FileAccess.get_file_as_string(_path(entry, GOLDEN))
	assert_false(text.contains("\r"), entry + ": CR found")
	assert_true(text.ends_with("}\n"), entry + ": must end with exactly one LF")


func test_top_level_shape(entry = use_parameters(SUCCESS_ENTRIES)) -> void:
	var golden = _golden(entry)
	assert_eq_deep(_sorted_keys(golden), _sorted(TOP_LEVEL_KEYS))
	assert_eq(golden.get("contract_version"), CONTRACT_VERSION, entry)


func test_line_mappings_cover_every_line_in_order(entry = use_parameters(SUCCESS_ENTRIES)) -> void:
	# include_non_executable = true (corpus default), so every line appears.
	assert_true(_config(entry).include_non_executable, entry + ": test assumes the corpus default")
	var mappings: Array = _golden(entry).get("line_mappings", [])
	var lines = _source_lines(entry)
	assert_eq(mappings.size(), lines.size(), entry + ": one mapping per source line")
	for i in mappings.size():
		var mapping: Dictionary = mappings[i]
		assert_eq_deep(_sorted_keys(mapping), _sorted(MAPPING_KEYS))
		var line = mapping.get("original_line")
		var label = "%s mapping #%d original_line" % [entry, i]
		if _assert_line_number(line, label):
			assert_eq(int(line), i + 1, label)


func test_classifications_match_spec(entry = use_parameters(SUCCESS_ENTRIES)) -> void:
	var expected: String = CLASS_MAP[entry]
	var mappings: Array = _golden(entry).get("line_mappings", [])
	assert_eq(mappings.size(), expected.length(), entry)
	for i in mini(mappings.size(), expected.length()):
		assert_eq(
			mappings[i].get("classification"),
			CLASS_NAMES[expected[i]],
			"%s line %d" % [entry, i + 1]
		)


func test_executable_lines_match_spec(entry = use_parameters(SUCCESS_ENTRIES)) -> void:
	assert_eq_deep(_ints(_golden(entry).get("executable_lines", [])), EXECUTABLE[entry])


func test_skipped_lines_match_spec(entry = use_parameters(SUCCESS_ENTRIES)) -> void:
	assert_eq_deep(_ints(_golden(entry).get("skipped_lines", [])), SKIPPED[entry])


func test_executable_and_skipped_partition_all_lines(
	entry = use_parameters(SUCCESS_ENTRIES)
) -> void:
	var golden = _golden(entry)
	var executable = _ints(golden.get("executable_lines", []))
	var skipped = _ints(golden.get("skipped_lines", []))
	for line in executable:
		assert_false(
			skipped.has(line), "%s: line %d is both executable and skipped" % [entry, line]
		)
	var union = executable + skipped
	union.sort()
	var all_lines = range(1, _source_lines(entry).size() + 1)
	assert_eq_deep(union, all_lines)
	assert_eq_deep(executable, _sorted(executable))
	assert_eq_deep(skipped, _sorted(skipped))


func test_lists_agree_with_line_mappings(entry = use_parameters(SUCCESS_ENTRIES)) -> void:
	var golden = _golden(entry)
	var from_mappings_exec = []
	var from_mappings_skip = []
	for mapping in golden.get("line_mappings", []):
		var line = int(mapping.original_line)
		if mapping.classification == "executable":
			from_mappings_exec.append(line)
		else:
			from_mappings_skip.append(line)
	assert_eq_deep(_ints(golden.get("executable_lines", [])), from_mappings_exec)
	assert_eq_deep(_ints(golden.get("skipped_lines", [])), from_mappings_skip)


func test_hit_record_inserted_follows_config(entry = use_parameters(SUCCESS_ENTRIES)) -> void:
	var enabled: bool = _config(entry).enable_instrumentation
	for mapping in _golden(entry).get("line_mappings", []):
		var expected = enabled and mapping.classification == "executable"
		assert_eq(
			mapping.get("hit_record_inserted"),
			expected,
			"%s line %d" % [entry, int(mapping.original_line)]
		)


func test_functions_match_spec_block(entry = use_parameters(SUCCESS_ENTRIES)) -> void:
	var spec_blocks = _spec_function_blocks()
	var spec_entry = COPY_OF.get(entry, entry)
	assert_has(spec_blocks, spec_entry, "spec has no FunctionMetadata block for " + spec_entry)
	if not spec_blocks.has(spec_entry):
		return
	var actual = _normalized_functions(_golden(entry).get("functions", []))
	assert_eq_deep(actual, _normalized_functions(spec_blocks[spec_entry]))


func test_function_ranges_fit_the_source(entry = use_parameters(SUCCESS_ENTRIES)) -> void:
	var lines = _source_lines(entry)
	var mappings: Array = _golden(entry).get("line_mappings", [])
	for function in _normalized_functions(_golden(entry).get("functions", [])):
		var label = "%s %s" % [entry, function.name]
		var start: int = function.start_line
		var end: int = function.end_line
		assert_true(start >= 1 and start < end and end <= lines.size(), label + ": bad range")
		if not (start >= 1 and start < end and end <= lines.size()):
			continue
		var header = lines[start - 1].strip_edges()
		assert_true(
			(
				header.begins_with("func " + function.name + "(")
				or header.begins_with("static func " + function.name + "(")
			),
			label + ": start_line is not the header"
		)
		assert_eq(function.is_static, header.begins_with("static "), label + ": is_static")
		assert_eq(mappings[start - 1].classification, "structural", label + ": header class")
		var indent = _indent(lines[start - 1])
		for i in range(start, end):
			if lines[i].strip_edges() != "":
				assert_gt(_indent(lines[i]), indent, "%s: line %d outside body" % [label, i + 1])
		assert_ne(lines[end - 1].strip_edges(), "", label + ": end_line is blank")
		for i in range(end, lines.size()):
			if lines[i].strip_edges() == "":
				continue
			assert_true(_indent(lines[i]) <= indent, label + ": body continues past end_line")
			break


func test_disabled_golden_differs_from_basic_only_in_hit_flags() -> void:
	var disabled = _golden("disabled_instrumentation")
	var basic = _golden("basic_statements")
	assert_false(disabled.get("line_mappings", []).is_empty(), "disabled golden is empty")
	for key in ["executable_lines", "skipped_lines", "functions"]:
		assert_eq_deep(disabled.get(key), basic.get(key))
	var basic_mappings: Array = basic.get("line_mappings", [])
	var disabled_mappings: Array = disabled.get("line_mappings", [])
	assert_eq(disabled_mappings.size(), basic_mappings.size())
	var any_basic_hit = false
	for i in mini(basic_mappings.size(), disabled_mappings.size()):
		assert_eq(disabled_mappings[i].classification, basic_mappings[i].classification)
		assert_false(disabled_mappings[i].hit_record_inserted, "disabled line %d" % (i + 1))
		any_basic_hit = any_basic_hit or basic_mappings[i].hit_record_inserted
	assert_true(any_basic_hit, "basic_statements must insert recorders, or the goldens match")


func _path(entry: String, file: String) -> String:
	return "%s/%s/%s" % [CORPUS_DIR, entry, file]


func _golden(entry: String) -> Dictionary:
	var path = _path(entry, GOLDEN)
	if not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}


func _config(entry: String) -> Dictionary:
	var config = CORPUS_DEFAULTS.duplicate()
	var path = _path(entry, "config.json")
	if FileAccess.file_exists(path):
		var overrides = JSON.parse_string(FileAccess.get_file_as_string(path))
		if overrides is Dictionary:
			config.merge(overrides, true)
	return config


# Contract §9.1: split on "\n". A file's final "\n" terminates its last line;
# it does not start an extra empty line.
func _source_lines(entry: String) -> PackedStringArray:
	var text = FileAccess.get_file_as_string(_path(entry, "source.gd"))
	if text.ends_with("\n"):
		text = text.left(-1)
	return text.split("\n")


func _spec_text() -> String:
	for file in DirAccess.get_files_at(SPEC_DIR):
		if file.begins_with(SPEC_PREFIX) and file.ends_with(".md"):
			return FileAccess.get_file_as_string("%s/%s" % [SPEC_DIR, file])
	return ""


# entry -> parsed "Expected FunctionMetadata" JSON block from the spec.
func _spec_function_blocks() -> Dictionary:
	var result = {}
	var heading = RegEx.create_from_string("^\\d+\\. `([a-z_]+)\\.gd`")
	var open_fence = "```json\n"
	for section in _spec_text().split("\n#### "):
		var found = heading.search(section)
		var marker = section.find("**Expected FunctionMetadata**")
		if found == null or marker == -1:
			continue
		var start = section.find(open_fence, marker)
		if start == -1:
			continue
		start += open_fence.length()
		var end = section.find("\n```", start)
		if end == -1:
			continue
		result[found.get_string(1)] = JSON.parse_string(section.substr(start, end - start))
	return result


func _normalized_functions(functions) -> Array:
	var result = []
	if not functions is Array:
		return result
	for function in functions:
		assert_eq_deep(_sorted_keys(function), _sorted(FUNCTION_KEYS))
		var label = "function %s" % function.get("name")
		assert_eq(typeof(function.get("name")), TYPE_STRING, label + ": name type")
		assert_eq(typeof(function.get("class_scope")), TYPE_STRING, label + ": class_scope type")
		assert_eq(typeof(function.get("is_static")), TYPE_BOOL, label + ": is_static type")
		_assert_line_number(function.get("start_line"), label + ": start_line")
		_assert_line_number(function.get("end_line"), label + ": end_line")
		(
			result
			. append(
				{
					"name": str(function.get("name", "")),
					"start_line": int(function.get("start_line", 0)),
					"end_line": int(function.get("end_line", 0)),
					"class_scope": str(function.get("class_scope", "")),
					"is_static": bool(function.get("is_static", false)),
				}
			)
		)
	return result


func _indent(line: String) -> int:
	return line.length() - line.lstrip("\t").length()


# Godot parses every JSON number as a float. A line number must be a JSON
# number holding a whole value >= 1, never a string or a fraction that int()
# would silently coerce into a valid-looking line.
func _assert_line_number(value, label: String) -> bool:
	var valid = typeof(value) == TYPE_FLOAT and value == floorf(value) and value >= 1.0
	assert_true(valid, "%s: %s is not a whole line number >= 1" % [label, var_to_str(value)])
	return valid


func _ints(values: Array) -> Array:
	var result = []
	for value in values:
		if _assert_line_number(value, "line list entry"):
			result.append(int(value))
	return result


func _sorted(values: Array) -> Array:
	var copy = values.duplicate()
	copy.sort()
	return copy


func _sorted_keys(dict: Dictionary) -> Array:
	return _sorted(dict.keys())
