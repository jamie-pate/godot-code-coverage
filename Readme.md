# Godot Code Coverage tool

Currently supports Godot 3.5

## Collect code coverage for GDScript

### Getting Started

Before running tests in this example repo you should first run `./update_addons.sh`

### Usage

For the example project you can run coverage like this to run the gut tests

`godot -s addons/gut/gut_cmdln.gd`

or to run coverage directly without GUT you can use

`godot -s addons/coverage/CoverageTree.gd --scene=res://Spatial.tscn`

After the `Coverage` instance is created and until `Coverage.instance().finalize()` the singleton will monitor the scene tree and ensure that no nodes are added with GDScript which are not excluded or instrumented.

`run_tests.sh path/to/godot` will run both examples and merge the coverage results.

* You can pass additional arguments to run_tests to specify the coverage targets:
	* e.g. `run_tests.sh path/to/godot 99 90 4` will require 99% total coverage and 90% file coverage, which will cause the test to fail, while setting verbosity to 4.

### Coverage Requirements

So far coverage requirements are left to the consumer. You can call `Coverage.instance().get_percent()` to get the full coverage percentage
and make a pass/fail decision based on that number. If you are using the `Gut` addon you can put this in a post run hook.

See this project's `tests/pre_run_hook.gd`, `tests/post_run_hook.gd` and `.gutconfig.json` for examples.

### Merging Coverage

You may have multiple separate test environments which require separate runs with coverage. In this case you can
combine the coverage from multiple test runs to meet an overall coverage target.

You can output a JSON file during tests using `Coverage.save_coverage_file(filename)`, then pass multiple coverage files to the `addons/merge_coverage.gd` script.

`godot -s addons/coverage/merge_coverage.gd [flags] file1.json file2.json [...fileN.json]`

flags:
* `--verbosity 3` : Set the verbosity of the coverage output. See Coverage.gd:Verbosity for levels.
* `--target 100` : set the coverage target, exit with failure if the target isn't met over all files
* `--file-target 100` : set the coverage target for individual files. exit with failure if the target isn't met
* `--output-file output.json` : Save the merged coverage to this file

See `run_tests.sh` for an example.

### API

#### `Coverage` class:

* `Coverage.new(scene_tree: SceneTree, exclude_paths := [])`
    * Initialize the coverage singleton. Until `Coverage.instance().finalize()` has been called you may access the singleton with `Coverage.instance()`
    * `exclude_paths` is a list of resource paths to be skipped when instrumenting files. It follows the [`String.match`](https://docs.godotengine.org/en/stable/classes/class_string.html#class-string-method-match) syntax from GDScript.
* `static func instance(strict := true) -> Coverage`: Returns the current singleton instance. Must be created first with `Coverage.new(...)`. May be called before calling `Coverage.new()` if strict is `false`, in which case it returns `null` if there is no instance.
* `static func finalize(print_verbose = false)`: Remove the singleton instance and print out the final coverage results. Pass `true` to print a verbose accounting of coverage for all files.
* `func instrument_scripts(path: String)`: **Recommended Approach** Recursively instrument all `*.gd` files within the requested path. Respects the `exclude_paths` argument passed to the constructor.
    * Returns `self` for chaining
* `func instrument_scene_scripts(scene: PackedScene)`: Instrument all scripts and their preloaded dependencies for a specific scene. `instrument_scripts` is probably more reliable.
    * Returns `self` for chaining
* `func instrument_autoloads()`: Just instrument autoload nodes that may have already been loaded. It's recommended to use `instrument_scripts` instead.
    * Returns `self` for chaining
* `func enforce_node_coverage()`: Enables monitoring on scene tree updates and asserts that all nodes must have script coverage.
    * Returns `self` for chaining
* `func get_coverage_collector(script_name: String) -> ScriptCoverageCollector`: Obtain the coverage collector for a specific script path, or null if it doesn't exist.
* `func set_coverage_targets(total: float, file: float)`: Set targets for coverage. Should be called before `finalize()`
* `func coverage_passing() -> bool`: Check coverage targets and return true if they are all passing.
* `func coverage_count() -> int`: Return the total number of lines which have been covered for all scripts.
* `func coverage_line_count() -> int`: Return the total number of lines which have been instrumented for the all script.
* `func coverage_percent() -> int`: Return the aggregate coverage percent (out of 100%) for all scripts.
* `func script_coverage(verbosity := Coverage.Verbosity.None) -> String`: Return a string which describes the script coverage. Check Coverage.Verbosity for possible values
* `func save_coverage_file(filename: String) -> bool`: Save the coverage to a json file for use with `merge_coverage_file` or `merge_coverage.gd`
* `func merge_from_coverage_file(filename: String, auto_instrument := true) -> bool`: Merge a coverage file into the current coverage. If you don't wish to instrument the files set auto_instrument to false.

#### `ScriptCoverage` class:

An internal class which represents coverage for a specific script, but does not attempt to instrument the script.

* `func coverage_count() -> int`: Return the number of lines which have been covered for the script.
* `func coverage_line_count() -> int`: Return the total number of lines which have been instrumented for the script.
* `func coverage_percent() -> int`: Return the coverage percent (out of 100%) for the script.
* `func script_coverage(verbosity := Coverage.Verbosity.None, target_coverage: float) -> String`: Return a string which describes coverage for the script.
* `func get_coverage_json() -> Dictionary`: Return the coverage as a dictionary suitable for saving to a json file.
* `func merge_coverage_json(coverage_json: Dictionary)`: Combine `coverage_json` with the currently captured coverage for the script.
* `func add_line_coverage(line_number: int, count := 1)`: Add coverage for a specific line for the script.
#### `ScriptCoverageCollector` class:

* Extends `ScriptCoverage`

An internal class which instruments a single GDScript and collects line coverage for that script.


#### API Examples

Most likely you will wish to combine this coverage utility with a testing library. For examples refer to `tests/pre_run_hook.gd`, `tests/post_run_hook.gd` and `.gutconfig.json`.

`pre_run_hook.gd`

```Python
extends "res://addons/gut/hook_script.gd"

const Coverage = preload("res://addons/coverage/Coverage.gd")
const exclude_paths = [
	"res://addons/*",
	# NOTE: Godot may crash if you try to instrument the script that's calling instrument_scripts()
	"res://tests/*",
	"res://contrib/*"
]

func run():
	Coverage.new(gut.get_tree(), exclude_paths)
	Coverage.instance().instrument_scripts("res://")
```

`post_run_hook.gd`

```Python
extends "res://addons/gut/hook_script.gd"

const Coverage = preload("res://addons/coverage/Coverage.gd")

const COVERAGE_TARGET := 75.0
const FILE_TARGET := 33.0

func run():
	var coverage = Coverage.instance()
	var coverage_file := OS.get_environment("COVERAGE_FILE") if OS.has_environment("COVERAGE_FILE") else ""
	if coverage_file:
		coverage.save_coverage_file(coverage_file)
	coverage.set_coverage_targets(COVERAGE_TARGET, FILE_TARGET)
	var verbosity = Coverage.Verbosity.FailingFiles
	coverage.finalize(verbosity)
	var logger = gut.get_logger()
	var coverage_passing = coverage.coverage_passing()
	if !coverage_passing:
		logger.failed("Coverage target of %.1f%% total (%.1f%% file) was not met" % [COVERAGE_TARGET, FILE_TARGET])
		set_exit_code(2)
	else:
		gut.set_log_level(gut.LOG_LEVEL_ALL_ASSERTS)
		logger.passed("Coverage target of %.1f%% total, %.1f%% file coverage" % [COVERAGE_TARGET, FILE_TARGET])
```

You may use the `CoverageTree.gd` as an example of the simplest use of the api.

Here is an abridged sample that adds coverage to all scripts in a scene, then runs the scene and prints coverage when the get_tree().quit() is called.

```Python
const Coverage = preload("./Coverage.gd")
const packed_scene = preload("res://Spatial.tscn")

func _initialize():
	# pass in the scene tree
	Coverage.new(self)
	Coverage.instance().instrument_scene_scripts(packed_scene)
	add_child(packed_scene.instance())

func _finalize():
	var coverage_file := OS.get_environment("COVERAGE_FILE") if OS.has_environment("COVERAGE_FILE") else ""
	if coverage_file:
		coverage.save_coverage_file(coverage_file)
	Coverage.finalize(Coverage.Verbosity.AllFiles)

```


## Troubleshooting

### Godot is Crashing

Make sure you **exclude your test scripts**, especially `pre_run_hook.gd` from being instrumented.
Godot will crash without warning if an currently running script is reloaded!

### My code isn't getting coverage

Some situations can't get coverage. For example any **autoload** nodes will not get coverage in their _ready() functions.

### Performance Issues

There is a performance test in the test that compares the instrumented code to the uninstrumented code. It is a microbenchmark so should be taken with a grain of salt, but when running operations like `array[i] /= 2` the instrumented code is roughly 1.7x slower than uninstrumented code. array.append(line_number) is the fastest way I've found to record that a line has been covered, deferring more expensive operations.

If you have trouble with instrumenting performance tests you should exclude that code from coverage if you can't figure out a way to make it faster than I have.

You may also use `ScripCoverageCollector.set_instrumented(value := true)` to de-instrument a script temporarily:

```Python
var coverage_collector = Coverage.instance().get_coverage_collector(HeapQueue.resource_path)
coverage_collector.set_instrumented(false)

# some performance critical test code

coverage_collector.set_instrumented(true)
```
