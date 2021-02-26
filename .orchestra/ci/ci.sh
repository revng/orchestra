#!/bin/bash

# rev.ng CI entrypoint script
# This script checks out the correct configuration branch and initializes
# variables for the actual CI script (ci-run.sh)
#
# Parameters are supplied as environment variables.
#
# Optional parameters:
#
# PUSHED_REF:
#   orchestra config commit/branch to use.
#   Normally set by Gitlab or whoever triggers the CI.

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ORCHESTRA_DIR="$DIR/../.."

# Runs git in the orchestra directory
function ogit () {
    git -C "$ORCHESTRA_DIR" "$@"
}

function log() {
    echo "$1" > /dev/stderr
}

set -e
set -x

# Determine target branch
#
# PUSHED_REF contains the git ref that was pushed and triggered the CI.
#
# If this ref is a branch, it will be used as the first default branch to try
# for all components and for orchestra configuration

COMPONENT_TARGET_BRANCH=""

if [[ -n "$PUSHED_REF" ]]; then
    if [[ "$PUSHED_REF" = refs/heads/* ]]; then
        COMPONENT_TARGET_BRANCH="${PUSHED_REF#refs/heads/}"
    else
        log "PUSHED_REF ($PUSHED_REF) is not a branch, bailing out"
        exit 0
    fi
fi

# Switch orchestra to the target branch or try the default list
ogit fetch
for B in "$COMPONENT_TARGET_BRANCH" next-develop develop next-master master; do
    if ogit checkout "$B"; then
        ORCHESTRA_TARGET_BRANCH="$B"
        break
    fi
done

if [[ -z "$ORCHESTRA_TARGET_BRANCH" ]]; then
    echo "[!] All checkout attempts failed, aborting"
    exit 1
fi

ORCHESTRA_CONFIG_COMMIT="$(ogit rev-parse --short "$ORCHESTRA_TARGET_BRANCH")"
echo "[+] Using configuration branch $ORCHESTRA_TARGET_BRANCH "\
     "(commit $ORCHESTRA_CONFIG_COMMIT)"

export COMPONENT_TARGET_BRANCH

# Run "true" CI script
"$DIR/ci-run.sh"
