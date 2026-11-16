extends GutTest

# Checks every corpus entry directory holds exactly the artifacts its pipeline
# requires (Contract v1.4 §13; Seed Corpus Specification acceptance criteria),
# and that tests/corpus/README.md exists (#7).
#
# Artifacts that later Epics deliver are allowed but not required yet:
# expected.instrumented.gd for the other success entries (#28),
# expected_hits.json (#29), and exercise.gd, which stays conditional until #23
# decides the exercise mechanism (§13: completeness checks do not test for it).

const CORPUS_DIR = "res://tests/corpus"

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
const FAILURE_ENTRIES = ["edge_cases_unsupported_syntax", "edge_cases_invalid_config"]

const COMMON_REQUIRED = ["source.gd", "source.gd.uid"]
const SUCCESS_REQUIRED = ["expected.metadata.json"]
const FAILURE_REQUIRED = ["expected.error.json"]
const SUCCESS_PENDING = ["expected.instrumented.gd", "expected_hits.json", "exercise.gd"]

# Per-entry artifacts beyond the pipeline's common set. config.json may exist
# only in these two entries (spec acceptance criteria).
const EXTRA_REQUIRED = {
	"disabled_instrumentation": ["config.json", "expected.instrumented.gd"],
	"edge_cases_invalid_config": ["config.json"],
}

var all_entries = SUCCESS_ENTRIES + FAILURE_ENTRIES


func test_readme_exists() -> void:
	var path = CORPUS_DIR + "/README.md"
	assert_true(FileAccess.file_exists(path), path + " is missing")


func test_entry_has_every_required_artifact(entry = use_parameters(all_entries)) -> void:
	var files = _files(entry)
	for artifact in _required(entry):
		assert_has(files, artifact, "%s is missing %s" % [entry, artifact])


func test_entry_has_no_unexpected_files(entry = use_parameters(all_entries)) -> void:
	var allowed = _required(entry)
	if SUCCESS_ENTRIES.has(entry):
		allowed += SUCCESS_PENDING
		allowed.append("exercise.gd.uid")
	for file in _files(entry):
		assert_has(allowed, file, "%s has unexpected file %s" % [entry, file])


func test_corpus_has_no_stray_files_at_top_level() -> void:
	assert_eq_deep(Array(DirAccess.get_files_at(CORPUS_DIR)), ["README.md"])


func _required(entry: String) -> Array:
	var required = COMMON_REQUIRED.duplicate()
	required += SUCCESS_REQUIRED if SUCCESS_ENTRIES.has(entry) else FAILURE_REQUIRED
	required += EXTRA_REQUIRED.get(entry, [])
	return required


# Files in an entry directory, without the .uid sidecars Godot generates for
# expected.*.gd goldens: those are ignored by .gitignore, not committed (#6).
func _files(entry: String) -> Array:
	var files = []
	for file in DirAccess.get_files_at("%s/%s" % [CORPUS_DIR, entry]):
		if file.begins_with("expected.") and file.ends_with(".gd.uid"):
			continue
		files.append(file)
	return files
