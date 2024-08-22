#!/usr/bin/env bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

PROGRAM="$(basename $0)"
BASE_PROGRAM="$(basename $0 | sed 's|.*-||')"
ROOT="$(readlink -f $DIR/..)"

exec -a "$PROGRAM" "$DIR/$BASE_PROGRAM" --sysroot "$ROOT" "$@"
