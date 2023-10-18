extends "res://addons/gut/hook_script.gd"

const Coverage = preload("res://addons/coverage/Coverage.gd")
const exclude_paths = [
	"res://addons/*",
	"res://tests/*",
	"res://contrib/*"
]

func run():
	Coverage.new(gut.get_tree(), exclude_paths) \
		super.instrument_scripts("res://") \
		super.enforce_node_coverage()
