# shellcheck shell=bash disable=SC2034
set -euo pipefail

function install_command() {
  PYTHON_PACKAGE_BASE=$("${ORCHESTRA_DOTDIR}/support/get-python-path" purelib)
  COMMANDS_DIR="${DESTDIR}${PYTHON_PACKAGE_BASE}/revng/internal/cli/_commands"
  mkdir -p "$COMMANDS_DIR"
  cp -a "$1" "$COMMANDS_DIR"
}

# Repackage vsixs inside the destination directory. This function will unzip
# all .vsix files specified and put them in the extension directory
function copy_extensions() {
  local EXTENSIONS_DIR="$1"
  shift;

  for extension in "$@"; do
    # We need a temporary directory since:
    # * unzip does not have the equivalent of --strip-components
    # * we need to read the extension's name from the package.json file
    TEMP=$(mktemp -d --tmpdir tmp.revng.vscode-web-ext-unpack.XXXXXXXXXX)
    # Inside the vsix there's a couple of manifest files in the root, these are for the
    # marketplace, whereas the `extension` directory contains the actual extension files
    # that need to be included
    unzip -qq "$ORCHESTRA_ROOT/$extension" 'extension/*' -d"$TEMP"
    NAME=$(jq -r .name "$TEMP/extension/package.json")
    cp -raT "$TEMP/extension" "$EXTENSIONS_DIR/$NAME"
    rm -rf "$TEMP"
  done
}

function remove_extraneous_extensions() {
  local PRODUCT_JSON="$1"
  local EXTENSIONS_DIR="$2"

  EXTENSIONS=$(jq -r '.builtinExtensions[]' "$PRODUCT_JSON")

  pushd "$EXTENSIONS_DIR" &> /dev/null

  # We compare the list of folders in the current directory (the extensions directory) to the list
  # of extensions that we specified in builtinExtensions, and we'll delete any that do not appear in
  # the latter
  readarray -t EXTRANEOUS_EXTENSIONS < \
    <(comm -23 \
      <(find . -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort) \
      <(echo "$EXTENSIONS" | sort))
  rm -rf "${EXTRANEOUS_EXTENSIONS[@]}"

  popd &> /dev/null
}
