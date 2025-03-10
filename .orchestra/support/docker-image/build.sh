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
# ./build.sh test-image .orchestra/binary-archives/.../none_master.tar.xz
# ./build.sh test-image .orchestra/binary-archives/.../none_af09<...>.tar.xz

SCRIPT_DIR=$(realpath "$(dirname "${BASH_SOURCE[0]}")")

NAME="$1"
INPUT="$2"
shift 2;

if [ -f "$INPUT" ]; then
    CONTEXT_DIR=$(mktemp --tmpdir -d tmp.podman-context-XXXXXXXXXX)
    trap 'rm -rf "$CONTEXT_DIR"' EXIT
    tar -C "$CONTEXT_DIR" --strip-components=1 -xf "$INPUT"
else
    CONTEXT_DIR="$INPUT"
fi

podman build -t "$NAME" -f "$SCRIPT_DIR/Dockerfile" "$CONTEXT_DIR" "$@"
