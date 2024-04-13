# Update addons directory from contrib submodules
DIR=$(dirname "${BASH_SOURCE[0]}")
DIR=$(realpath "${DIR}")
cd $DIR

if [ "${1:-}" != "--no-init" ]; then
    git submodule update --init --recursive
fi
cp -R contrib/Gut/addons/gut addons
