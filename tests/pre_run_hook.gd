extends GutHookScript

const Coverage = preload("res://addons/coverage/Coverage.gd")
const exclude_paths = [
	"res://addons/*",
	"res://tests/*",
	"res://contrib/*"
]

func run():
	Coverage.new(gut.get_tree(), exclude_paths) \
		.instrument_scripts("res://") \
		.enforce_node_coverage()
