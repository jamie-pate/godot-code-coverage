# Godot Code Coverage tool

Currently supports Godot 3.5

## Collect code coverage for GDScript

### Getting Started

To run the tests in this example repo you should run `./update_addons.sh`

### Usage

For the example project you can run coverage like this to run the gut tests

`godot -s addons/gut/gut_cmdln.gd`

or to run coverage directly without GUT you can use

`godot -s addons/coverage/CoverageTree.gd --scene=res://Spatial.tscn`

After the `Coverage` instance is created and until `Coverage.instance().finalize()` the singleton will monitor the scene tree and ensure that no nodes are added with GDScript which are not excluded or instrumented.

### Coverage Requirements

So far coverage requirements are left to the consumer. You can call `Coverage.instance().get_percent()` to get the full coverage percentage
and make a pass/fail decision based on that number. If you are using the `Gut` addon you can put this in a post run hook.

See this project's `tests/pre_run_hook.gd`, `tests/post_run_hook.gd` and `.gutconfig.json` for examples.

### API

#### `Coverage` class:

* `Coverage.new(scene_tree: SceneTree, exclude_paths := [])`
    * Initialize the coverage singleton. Until `Coverage.instance().finalize()` has been called you may access the singleton with `Coverage.instance()`
    * `exclude_paths` is a list of resource paths to be skipped when instrumenting files. It follows the [`String.match`](https://docs.godotengine.org/en/stable/classes/class_string.html#class-string-method-match) syntax from GDScript.
* `static func instance() -> Coverage`: Returns the current singleton instance. Must be created first with `Coverage.new(...)`
* `static func finalize(print_verbose = false)`: Remove the singleton instance and print out the final coverage results. Pass `true` to print a verbose accounting of coverage for all files.
* `func instrument_scene_scripts(scene: PackedScene)`: Instrument all scripts and their preloaded dependencies for a specific scene. `instrument_scripts` is probably more reliable.
    * Returns `self` for chaining
* `func instrument_scripts(path: String)`: Recursively instrument all `*.gd` files within the requested path. Respects the `exclude_paths` argument passed to the constructor.
    * Returns `self` for chaining
* `func instrument_autoloads()`: Instrument any autoload nodes that may have already been loaded.
    * Returns `self` for chaining
* `func enforce_node_coverage()`: Enables monitoring on scene tree updates and asserts that all nodes must have script coverage.
    * Returns `self` for chaining
* `func get_coverage_collector(script_name: String) -> ScriptCoverageCollector`: Obtain the coverage collector for a specific script path, or null if it doesn't exist.
* `func coverage_count() -> int`: Return the total number of lines which have been covered for all scripts.
* `func coverage_line_count() -> int`: Return the total number of lines which have been instrumented for the all script.
* `func coverage_percent() -> int`: Return the aggregate coverage percent (out of 100%) for all scripts.
* `func script_coverage(verbose := false) -> String`: Return a string which describes the script coverage. If verbose is true then coverage for each file will be described.

#### `ScriptCoverageCollector` class:

An internal class which instruments a single GDScript and collects line coverage for that script.

* `func coverage_count() -> int`: Return the number of lines which have been covered for the script.
* `func coverage_line_count() -> int`: Return the total number of lines which have been instrumented for the script.
* `func coverage_percent() -> int`: Return the coverage percent (out of 100%) for the script.

#### API Examples

Most likely you will wish to combine this coverage utility with a testing library. For examples refer to `tests/pre_run_hook.gd`, `tests/post_run_hook.gd` and `.gutconfig.json`.

`pre_run_hook.gd`

```Python
extends "res://addons/gut/hook_script.gd"

const Coverage = preload("res://addons/coverage/Coverage.gd")
const exclude_paths = [
	"res://addons/*",
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

const COVERAGE_TARGET = 91.0

func run():
	var coverage_percent = Coverage.instance().coverage_percent()
	Coverage.instance().finalize(true)
	var logger = gut.get_logger()
	if coverage_percent < COVERAGE_TARGET:
		logger.failed("Coverage target of %.1f%% was not met" % [COVERAGE_TARGET])
		set_exit_code(2)
	else:
		gut.set_log_level(gut.LOG_LEVEL_ALL_ASSERTS)
		logger.passed("Coverage target of %.1f%%" % [COVERAGE_TARGET])
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
    Coverage.finalize(true)

```
