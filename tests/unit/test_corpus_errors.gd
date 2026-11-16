extends GutTest

# Validates the expected.error.json goldens of the two expected-failure entries
# (#5) against Instrumentation Contract v1.4 (§3.3, §8, §12.2, §13.2) and the
# Seed Corpus Specification.
#
# Pinned values:
# - Sub-case A (edge_cases_unsupported_syntax): transcribed verbatim from #13
#   (UNSUPPORTED_SYNTAX, original_line 4, "bracket continuation is not
#   supported"). The spec's Sub-case A explanation is updated by #13.
# - Sub-case B (edge_cases_invalid_config): reason pinned in #5, to be
#   produced exactly by configuration validation (#9).

const CORPUS_DIR = "res://tests/corpus"
const GOLDEN = "expected.error.json"

const ERROR_KEYS = ["status", "original_line", "reason"]

# Contract §8, InstrumentationStatus.
const STATUSES = ["UNSUPPORTED_SYNTAX", "INVALID_SOURCE", "INVALID_CONFIGURATION"]

# Contract §3.3, supported hit_recorder_expression placeholders.
const PLACEHOLDERS = ["{line}", "{path}"]

const EXPECTED = {
	"edge_cases_unsupported_syntax":
	{
		"status": "UNSUPPORTED_SYNTAX",
		"original_line": 4,
		"reason": "bracket continuation is not supported",
	},
	"edge_cases_invalid_config":
	{
		"status": "INVALID_CONFIGURATION",
		"original_line": -1,
		"reason": "unknown placeholder {column} in hit_recorder_expression",
	},
}

var failure_entries = EXPECTED.keys()


func test_golden_exists_and_parses(entry = use_parameters(failure_entries)) -> void:
	var path = _path(entry, GOLDEN)
	assert_true(FileAccess.file_exists(path), path + " is missing")
	assert_false(_golden(entry).is_empty(), path + " is not a JSON object")


func test_golden_uses_lf_and_one_trailing_newline(entry = use_parameters(failure_entries)) -> void:
	var text = FileAccess.get_file_as_string(_path(entry, GOLDEN))
	assert_false(text.contains("\r"), entry + ": CR found")
	assert_true(text.ends_with("}\n"), entry + ": must end with exactly one LF")
	assert_false(text.ends_with("}\n\n"), entry + ": must end with exactly one LF")


func test_golden_has_exactly_the_contract_keys(entry = use_parameters(failure_entries)) -> void:
	assert_eq_deep(_sorted(_golden(entry).keys()), _sorted(ERROR_KEYS))


func test_status_is_a_contract_status(entry = use_parameters(failure_entries)) -> void:
	var status = _golden(entry).get("status")
	assert_eq(typeof(status), TYPE_STRING, entry + ": status type")
	assert_has(STATUSES, status, entry + ": status is not an InstrumentationStatus")


func test_golden_matches_pinned_values(entry = use_parameters(failure_entries)) -> void:
	var golden = _golden(entry)
	var expected: Dictionary = EXPECTED[entry]
	assert_eq(golden.get("status"), expected.status, entry + ": status")
	assert_eq(golden.get("reason"), expected.reason, entry + ": reason")
	var line = golden.get("original_line")
	# Godot parses every JSON number as a float; reject strings and fractions
	# that int() would silently coerce.
	assert_eq(typeof(line), TYPE_FLOAT, entry + ": original_line type")
	if typeof(line) == TYPE_FLOAT:
		assert_eq(line, floorf(line), entry + ": original_line is not whole")
		assert_eq(int(line), expected.original_line, entry + ": original_line")


func test_reason_is_a_single_trimmed_line(entry = use_parameters(failure_entries)) -> void:
	var reason = str(_golden(entry).get("reason", ""))
	assert_ne(reason, "", entry + ": empty reason")
	assert_eq(reason, reason.strip_edges(), entry + ": reason has surrounding whitespace")
	assert_false(reason.contains("\n"), entry + ": reason spans several lines")


func test_unsupported_syntax_line_is_where_the_bracket_opens() -> void:
	# #13: original_line is the line on which the unclosed bracket opened,
	# i.e. the first line whose bracket depth is still nonzero at its end.
	# Sub-case A contains no strings or comments, so plain counting is exact.
	var entry = "edge_cases_unsupported_syntax"
	var lines = _source_lines(entry)
	var depth = 0
	var opened_at = -1
	for i in lines.size():
		for character in lines[i]:
			if "([{".contains(character):
				depth += 1
			elif ")]}".contains(character):
				depth -= 1
		if depth != 0 and opened_at == -1:
			opened_at = i + 1
	assert_eq(depth, 0, entry + ": source must be balanced overall")
	assert_eq(int(_golden(entry).get("original_line", 0)), opened_at, entry)
	assert_false(FileAccess.file_exists(_path(entry, "config.json")), entry + ": uses defaults")


func test_invalid_config_has_only_an_unknown_placeholder() -> void:
	var entry = "edge_cases_invalid_config"
	var path = _path(entry, "config.json")
	assert_true(FileAccess.file_exists(path), path + " is missing")
	var config = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_true(config is Dictionary, path + " is not a JSON object")
	if not config is Dictionary:
		return
	assert_eq_deep(config.keys(), ["hit_recorder_expression"])
	var template = str(config.get("hit_recorder_expression", ""))
	assert_ne(template, "", entry + ": the empty-template case is not this entry")
	var unknown = _unknown_placeholders(template)
	assert_eq(unknown.size(), 1, entry + ": expected exactly one unknown placeholder")
	if unknown.size() == 1:
		assert_string_contains(str(_golden(entry).get("reason", "")), unknown[0])


func test_failure_entries_carry_no_success_goldens(entry = use_parameters(failure_entries)) -> void:
	# Contract §12.2: a failed transformation never exposes instrumented source.
	for artifact in ["expected.instrumented.gd", "expected.metadata.json", "expected_hits.json"]:
		assert_false(FileAccess.file_exists(_path(entry, artifact)), entry + ": " + artifact)


func _path(entry: String, file: String) -> String:
	return "%s/%s/%s" % [CORPUS_DIR, entry, file]


func _golden(entry: String) -> Dictionary:
	var path = _path(entry, GOLDEN)
	if not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}


# Contract §9.1: split on "\n"; the final "\n" ends the last line.
func _source_lines(entry: String) -> PackedStringArray:
	var text = FileAccess.get_file_as_string(_path(entry, "source.gd"))
	if text.ends_with("\n"):
		text = text.left(-1)
	return text.split("\n")


func _unknown_placeholders(template: String) -> Array:
	var unknown = []
	for found in RegEx.create_from_string("\\{[^{}]*\\}").search_all(template):
		var placeholder = found.get_string()
		if not PLACEHOLDERS.has(placeholder):
			unknown.append(placeholder)
	return unknown


func _sorted(values: Array) -> Array:
	var copy = values.duplicate()
	copy.sort()
	return copy
