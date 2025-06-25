#!/usr/bin/env bash
set -euo pipefail

# This script builds the revng docker image, using the Dockerfile from the
# directory where this script resides. It takes two arguments:
# $1: The image name to use
# $2: a path to the source for the revng installation, this can either be:
#     * A `.tar.gz` from binary archives of `revng-distributable(-public-demo)`
#     * The installation directory of `revng-distributable(-public-demo)`
# Examples
# ./build.sh test-image $ORCHESTRA_ROOT/revng
# ./build.sh test-image $ORCHESTRA_ROOT/revng-public-demo
# ./build.sh test-image .orchestra/binary-archives/.../master.tar.xz
# ./build.sh test-image .orchestra/binary-archives/.../af09<...>.tar.xz

SCRIPT_DIR=$(realpath "$(dirname "${BASH_SOURCE[0]}")")

NAME="$1"
INPUT="$2"
shift 2;

CONFIG_JSON="{"

if [ -f "$INPUT" ]; then
    CONTEXT_DIR=$(mktemp --tmpdir -d tmp.podman-context-XXXXXXXXXX)
    trap 'rm -rf "$CONTEXT_DIR"' EXIT
    tar -C "$CONTEXT_DIR" --strip-components=1 -xf "$INPUT"
    CONFIG_JSON+="\"last-archive\": \"$(basename "$(realpath "$INPUT")")\","
else
    CONTEXT_DIR="$INPUT"
fi

TOP_LEVEL_FILES="[$(find "$CONTEXT_DIR" -maxdepth 1 -mindepth 1 -printf '"%f",')"
CONFIG_JSON+="\"top-level-files\": ${TOP_LEVEL_FILES/%,/]},"

if [ -n "${BRANCH:-}" ]; then
    CONFIG_JSON+="\"branch\": \"$BRANCH\","
fi

podman build -t "$NAME" -f "$SCRIPT_DIR/Dockerfile" \
             --build-arg=CONFIG_JSON="${CONFIG_JSON/%,/}}" \
             "$CONTEXT_DIR" "$@"
