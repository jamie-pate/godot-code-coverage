# Update addons directory from contrib submodules
DIR=$(dirname "${BASH_SOURCE[0]}")
DIR=$(realpath "${DIR}")
cd $DIR

git submodule update --init
cp -R contrib/Gut/addons/gut addons
