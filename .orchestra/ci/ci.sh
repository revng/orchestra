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

set -euo pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ORCHESTRA_DIR="$DIR/../.."

BOLD="\e[1m"
RED="\e[31m"
RESET="\e[0m"

# Runs git in the orchestra directory
function ogit () {
    git -C "$ORCHESTRA_DIR" "$@"
}

function log() {
    echo -en "${BOLD}" > /dev/stderr
    echo -n '[+]' "$1" > /dev/stderr
    echo -e "${RESET}" > /dev/stderr
}

function log_err() {
    echo -en "${BOLD}${RED}" > /dev/stderr
    echo -n '[!]' "$1" > /dev/stderr
    echo -e "${RESET}" > /dev/stderr
}

function log2() {
    echo -en "${BOLD}" > /dev/stderr
    echo -n '[+]' "${1}" > /dev/stderr
    echo -en "${RESET} " > /dev/stderr
    echo "${2}" > /dev/stderr
}

# Determine target branch
#
# PUSHED_REF contains the git ref that was pushed and triggered the CI.
#
# If this ref is a branch, it will be used as the first default branch to try
# for all components and for orchestra configuration

COMPONENT_TARGET_BRANCH=""

if [[ -n "${PUSHED_REF:-}" ]]; then
    if [[ "$PUSHED_REF" = refs/heads/* ]]; then
        COMPONENT_TARGET_BRANCH="${PUSHED_REF#refs/heads/}"
    else
        log_err "PUSHED_REF ($PUSHED_REF) is not a branch, bailing out"
        exit 0
    fi
fi

ogit fetch

# If the target branch is not part of the default list and it does not already
# exist, create it
if [[ ! "$COMPONENT_TARGET_BRANCH" =~ ^(next-)?(develop|master)$ ]] && \
    ! git rev-parse --quiet --verify "$COMPONENT_TARGET_BRANCH" >/dev/null ; then
    log "Creating branch $COMPONENT_TARGET_BRANCH for orchestra configuration from master"
    ogit checkout "$COMPONENT_TARGET_BRANCH" || ogit checkout -b "$COMPONENT_TARGET_BRANCH" master
fi

# Switch orchestra to the target branch or try the default list
for B in "$COMPONENT_TARGET_BRANCH" next-develop develop next-master master; do
    if ogit checkout "$B"; then
        ORCHESTRA_TARGET_BRANCH="$B"
        break
    fi
done

if [[ -z "${ORCHESTRA_TARGET_BRANCH:-}" ]]; then
    log_err "All checkout attempts failed, aborting"
    exit 1
fi

ORCHESTRA_CONFIG_COMMIT="$(ogit rev-parse --short "$ORCHESTRA_TARGET_BRANCH")"

echo
echo -en "$BOLD"
echo "################################################################################"
echo "#                              BUILD INFORMATION                               #"
echo "################################################################################"
echo -e "$RESET"

log2 "Using orchestra config:" "${ORCHESTRA_TARGET_BRANCH} @ ${ORCHESTRA_CONFIG_COMMIT}"
log2 "Component:             " "${TARGET_COMPONENTS_URL:-[not set]}"
log2 "Branch:                " "${PUSHED_REF:-[not set]}"

if [[ "$PUSH_CHANGES" == 1 ]]; then
    BRANCH_PROMOTION="yes"
else
    BRANCH_PROMOTION="no"
fi

log2 "Promote branch:        " "$BRANCH_PROMOTION"

if test -n "${REVNG_CI_STATUS_UPDATE_METADATA:-}"; then
    PLATFORM="$(echo "$REVNG_CI_STATUS_UPDATE_METADATA" | jq -r '.platform')"
    if [[ "$PLATFORM" == "github" ]]; then
        REPO="$(echo "$REVNG_CI_STATUS_UPDATE_METADATA" | jq -r '.github_repository_name')"
        CHECK_RUN="$(echo "$REVNG_CI_STATUS_UPDATE_METADATA" | jq -r '.github_check_run_id')"
        USER="$(echo "$REVNG_CI_STATUS_UPDATE_METADATA" | jq -r '.triggering_user')"

        log2 "Source platform:       " "GitHub"
        log2 "Check run:             " "https://github.com/${REPO}/runs/${CHECK_RUN}"
        log2 "Triggered by:          " "$USER"
    else
        MR="$(echo "$REVNG_CI_STATUS_UPDATE_METADATA" | jq -r '.gitlab_mr_web_url')"
        SHA="$(echo "$REVNG_CI_STATUS_UPDATE_METADATA" | jq -r '.head_sha')"

        log2 "Source platform:       " "GitLab"
        log2 "Merge request:         " "$MR"
        log2 "HEAD commit:           " "$SHA"
    fi
fi

echo -e "$BOLD"
echo "################################################################################"
echo -e "$RESET"


# Install missing dependencies
.orchestra/ci/install-dependencies.sh

export COMPONENT_TARGET_BRANCH

# Run "true" CI script
log "Starting ci-run with COMPONENT_TARGET_BRANCH=$COMPONENT_TARGET_BRANCH"
"$DIR/ci-run.sh"
