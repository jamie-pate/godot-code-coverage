extends GutTest

# Validates the expected.instrumented.gd goldens (Contract v1.4 §13.1).
#
# Only disabled_instrumentation has one so far (#6): per Contract §3.1, with
# enable_instrumentation = false the instrumented source is identical to the
# original, so its golden is a byte-for-byte copy of its own source.gd. The
# other nine success entries get theirs in #28 (Epic #14).
#
# Goldens are read as text and never load()ed or preload()ed: an instrumented
# golden calls __coverage_hit(...), which does not exist, so loading one as a
# script is a parse error (docs/corpus-golden-gd-verification.md).

const CORPUS_DIR = "res://tests/corpus"
const GOLDEN = "expected.instrumented.gd"

# Entries whose golden must equal their source, because instrumentation is
# disabled in their config.json.
const IDENTITY_ENTRIES = ["disabled_instrumentation"]

var identity_entries = IDENTITY_ENTRIES


func test_golden_exists(entry = use_parameters(identity_entries)) -> void:
	var path = _path(entry, GOLDEN)
	assert_true(FileAccess.file_exists(path), path + " is missing")


func test_entry_disables_instrumentation(entry = use_parameters(identity_entries)) -> void:
	# The identity golden is only valid under this override (Contract §3.1).
	var path = _path(entry, "config.json")
	assert_true(FileAccess.file_exists(path), path + " is missing")
	var config = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_true(config is Dictionary, path + " is not a JSON object")
	if config is Dictionary:
		assert_eq_deep(config, {"enable_instrumentation": false})


func test_golden_is_byte_identical_to_source(entry = use_parameters(identity_entries)) -> void:
	var golden_path = _path(entry, GOLDEN)
	var source_path = _path(entry, "source.gd")
	if not FileAccess.file_exists(golden_path):
		fail_test(golden_path + " is missing")
		return
	var golden = FileAccess.get_file_as_bytes(golden_path)
	var source = FileAccess.get_file_as_bytes(source_path)
	assert_false(source.is_empty(), source_path + " is empty")
	assert_true(golden == source, "%s differs from %s" % [golden_path, source_path])


func test_golden_uses_lf_and_has_no_recorders(entry = use_parameters(identity_entries)) -> void:
	var path = _path(entry, GOLDEN)
	if not FileAccess.file_exists(path):
		fail_test(path + " is missing")
		return
	var text = FileAccess.get_file_as_string(path)
	assert_false(text.contains("\r"), entry + ": CR found")
	assert_true(text.ends_with("\n"), entry + ": must end with LF")
	assert_false(text.contains("__coverage_hit"), entry + ": recorder inserted while disabled")


func _path(entry: String, file: String) -> String:
	return "%s/%s/%s" % [CORPUS_DIR, entry, file]
