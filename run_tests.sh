godot="${1:-godot}"
target=${2:-78}
file_target=${3:-33}
verbosity=${4:-3}
output_file="${5:-coverage_out.json}"

set -x

COVERAGE_FILE=coverage1.json "$godot" -s addons/coverage/CoverageTree.gd --scene=res://Spatial.tscn
COVERAGE_FILE=coverage2.json "$godot" -s addons/gut/gut_cmdln.gd
echo "MERGED COVERAGE:"
"$godot" -s addons/coverage/merge_coverage.gd --verbosity $verbosity --target $target --file-target $file_target --output-file "$output_file" coverage1.json coverage2.json
