# Update addons directory from contrib submodules
DIR=$(dirname "${BASH_SOURCE[0]}")
DIR=$(realpath "${DIR}")
cd "$DIR"

if [ "${1:-}" != "--no-init" ]; then
    git submodule update --init --recursive
fi
# Remove any previous copy first: copying into an existing addons/gut/
# nests it as addons/gut/gut/ (duplicate UIDs, a second GutUtils).
rm -rf addons/gut
cp -R contrib/Gut/addons/gut addons
