godot="${1:-godot}"
target=${2:-75}
file_target=${3:-30}
output_file="${4:-coverage_out.json}"

set -x

COVERAGE_FILE=coverage1.json "$godot" -s addons/coverage/CoverageTree.gd --scene=res://Spatial.tscn
COVERAGE_FILE=coverage2.json "$godot" -s addons/gut/gut_cmdln.gd
echo "MERGED COVERAGE:"
"$godot" -s addons/coverage/merge_coverage.gd --target $target --file-target $file_target --output-file "$output_file" coverage1.json coverage2.json
