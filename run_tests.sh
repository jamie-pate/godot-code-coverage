headless_flag=
if [ "${1:-}" == "--headless" ]; then
    headless_flag=--headless
    shift
fi

godot="${1:-godot}"
target=${2:-78}
file_target=${3:-33}
verbosity=${4:-3}
output_file="${5:-coverage_out.json}"

set -ex

COVERAGE_FILE=coverage1.json "$godot" $headless_flag -s addons/coverage/coverage_tree.gd --scene=res://spatial.tscn
COVERAGE_FILE=coverage2.json "$godot" $headless_flag -s addons/gut/gut_cmdln.gd -gexit
echo "MERGED COVERAGE:"
"$godot" $headless_flag -s addons/coverage/merge_coverage.gd --verbosity $verbosity --target $target --file-target $file_target --output-file "$output_file" coverage1.json coverage2.json
set +x
echo -n "MERGED COVERAGE can fail: "
if test_fail="$("$godot" $headless_flag -s addons/coverage/merge_coverage.gd --verbosity 0 --target 99 --file-target 99 coverage1.json coverage2.json 2>&1)"; then
    echo "Error, merge_coverage should not have passed:" >&2
    echo "$test_fail" >&2
    exit 1
else
    echo "OK"
fi
