#!/usr/bin/env bash
set -euo pipefail

# rev.ng CI script
# This script runs orchestra to build the required components.
# If the build is successful the script can push the newly produced binary
# archives and promote next-<name> branches to <name>.
#
# Parameters are supplied as environment variables.
#
# Target component is mandatory and done with these parameters:
#
# TARGET_COMPONENTS: list of components to build
# TARGET_COMPONENTS_URL:
#   list of glob patterns used to select additional target components
#   by matching their remote URL
#
# Mandatory parameters:
#
# COMPONENT_TARGET_BRANCH:
#   the branch which the CI has been run against. Will influence a few strings
#   throughout the CI. It will also change which branch name to try first when
#   checking out component sources
# REVNG_ORCHESTRA_URL: orchestra git repo URL (must be git+ssh:// or git+https://)
#
# Optional parameters:
#
# BASE_USER_OPTIONS_YML:
#   user_options.yml is initialized to this value.
#   %GITLAB_ROOT% is replaced with the base URL of the Gitlab instance.
# PUSH_BINARY_ARCHIVES: if == 1, push binary archives
# PROMOTE_BRANCHES: if == 1, promote next-* branches
# PUSH_CHANGES:
#   if == 1, push binary archives and promote next-* branches
# SSH_PRIVATE_KEY: private key used to push binary archives
# BUILD_ALL_FROM_SOURCE: if == 1 do not use binary archives and build everything
# LFS_RETRIES: Number of times lfs pull/push operations are retried. Defaults to 3.

SCRIPT_DIR=$(realpath "$(dirname "${BASH_SOURCE[0]}")")
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

PRIVATE_SOURCES_CLONE_URL="https://gitlab-ci-token:${CI_JOB_TOKEN:-}@rev.ng/gitlab/revng-private"
PRIVATE_BIN_ARCHIVES_CLONE_URL="https://gitlab-ci-token:${CI_JOB_TOKEN:-}@rev.ng/gitlab/revng-private/binary-archives.git"

PUSH_BINARY_ARCHIVES="${PUSH_BINARY_ARCHIVES:-}"
PROMOTE_BRANCHES="${PROMOTE_BRANCHES:-}"
PUSH_CHANGES="${PUSH_CHANGES:-}"

BOLD="\e[1m"
RED="\e[31m"
RESET="\e[0m"

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

if [[ "${BUILD_ALL_FROM_SOURCE:-}" == 1 ]]; then
    log "Build mode: building all components from source"
    BUILD_MODE="-B"
else
    log "Build mode: binary archives enabled"
    BUILD_MODE="-b"
fi

cd "$SCRIPT_DIR"

# Install dependencies
"$SCRIPT_DIR/install-dependencies.sh"

#
# Register deploy key, if any
#
if [ -n "${SSH_PRIVATE_KEY:-}" ]; then
    load_ssh_key

    # Change orchestra remote to ssh if we were given the URL
    if [[ -n "${ORCHESTRA_CONFIG_REPO_SSH_URL:-}" ]]; then
        git -C "$ORCHESTRA_REPO_DIR" remote set-url origin "$ORCHESTRA_CONFIG_REPO_SSH_URL"
    fi
fi

#
# Install orchestra
#
for REVNG_ORCHESTRA_TARGET_BRANCH in "$COMPONENT_TARGET_BRANCH" next-develop develop master; do
    if pip3 -q install --user "$REVNG_ORCHESTRA_URL@$REVNG_ORCHESTRA_TARGET_BRANCH"; then
        break
    fi
done

# Make sure we can run orchestra
export PATH="$HOME/.local/bin:$PATH"
command -v orc > /dev/null

#
# Prepare the user_options.yml file
#
if test -e "$USER_OPTIONS"; then
    log_err "$USER_OPTIONS already exists!"
    exit 1
fi

REMOTE="$(git remote get-url origin | sed 's|^\([^:]*:\)\([^/]\)|\1/\2|')"
GITLAB_ROOT="$(dirname "$(dirname "$REMOTE")")"

# Replace placeholders in provided user_options.yml with actual values:
# - %GITLAB_ROOT% -> $GITLAB_ROOT
# - %PRIVATE_SOURCES_PLACEHOLDER% - Private sources namespace with internal HTTP clone token
# - %PRIVATE_BIN_ARCHIVES_PLACEHOLDER% - Private binary archives repo with internal HTTP clone token
USER_OPTIONS_YML="${BASE_USER_OPTIONS_YML//\%GITLAB_ROOT\%/$GITLAB_ROOT}"
USER_OPTIONS_YML="${USER_OPTIONS_YML//\%PRIVATE_SOURCES_PLACEHOLDER\%/$PRIVATE_SOURCES_CLONE_URL}"
USER_OPTIONS_YML="${USER_OPTIONS_YML//\%PRIVATE_BIN_ARCHIVES_PLACEHOLDER\%/$PRIVATE_BIN_ARCHIVES_CLONE_URL}"

echo "${USER_OPTIONS_YML//\%GITLAB_ROOT\%/$GITLAB_ROOT}" > "$USER_OPTIONS"

# Build branches list
cat >> "$USER_OPTIONS" <<EOF
#@overlay/replace
branches:
EOF

if ! [[ "$COMPONENT_TARGET_BRANCH" =~ ^(next-)?(develop|master)$ ]]; then
    echo "  - $COMPONENT_TARGET_BRANCH" >> "$USER_OPTIONS"
fi

cat >> "$USER_OPTIONS" <<EOF
  - next-develop
  - develop
  - master
EOF

# Print debug information
log "User options:"
cat "$USER_OPTIONS"

orc update --no-config

# Register target components
# shellcheck disable=SC2153
if test -n "${TARGET_COMPONENTS_URL:-}"; then
    # Add components by repository URL
    for TARGET_COMPONENT_URL in $TARGET_COMPONENTS_URL; do
        NEW_COMPONENT="$(orc components --repository-url "$TARGET_COMPONENT_URL" \
                         | ( grep '^Component' || true ) \
                         | cut -d' ' -f2)"
        if test -z "$NEW_COMPONENT"; then
            log "Warning: ignoring URL $TARGET_COMPONENT_URL since it doesn't match any component"
        else
            TARGET_COMPONENTS="$NEW_COMPONENT $TARGET_COMPONENTS"
        fi
    done
fi

log "Target components: $TARGET_COMPONENTS"

if test -z "${TARGET_COMPONENTS:-}"; then
    log "Nothing to do!"
    exit 1
fi

if [[ "${ORCHESTRA_DEBUG:-}" == 1 ]]; then
    # Print debugging information
    log "Complete dependency graph"
    orc graph "$BUILD_MODE"
    for TARGET_COMPONENT in $TARGET_COMPONENTS; do
        log "Solved dependency graph for the target component $TARGET_COMPONENT"
        orc graph --solved "$BUILD_MODE" "$TARGET_COMPONENT"
    done
    log "Information about the components"
    orc components --hashes
    log "Binary archives commit"
    for BINARY_ARCHIVE_PATH in $(orc ls --binary-archives); do
        log "Commit for $BINARY_ARCHIVE_PATH: $(git -C "$BINARY_ARCHIVE_PATH" rev-parse HEAD)"
    done
fi

# Ensure we are doing a clean build
orc clean --all

#
# Actually run the build
#
ADDITIONAL_ORC_INSTALL_OPTIONS=()
if [[ "$PUSH_BINARY_ARCHIVES" = 1 || "$PUSH_CHANGES" = 1 ]]; then
    ADDITIONAL_ORC_INSTALL_OPTIONS+=(--create-binary-archives)
fi

ERRORS=0
for TARGET_COMPONENT in $TARGET_COMPONENTS; do
    log "Building target component $TARGET_COMPONENT"
    if ! orc --quiet install \
        --discard-build-directories \
        --lfs-retries "$LFS_RETRIES" \
        "$BUILD_MODE" \
        --test \
        "${ADDITIONAL_ORC_INSTALL_OPTIONS[@]}" \
        "$TARGET_COMPONENT";
    then
        ERRORS=1
        break
    fi
done

if [[ "$PUSH_BINARY_ARCHIVES" = 1 || "$PUSH_CHANGES" = 1 ]]; then
    orc symlink-binary-archives "${COMPONENT_TARGET_BRANCH////-}"
fi

if [[ "$PROMOTE_BRANCHES" = 1 || "$PUSH_CHANGES" = 1 ]]; then
    # Promote next-develop to develop
    if [[ "$ERRORS" -eq 0 && "$COMPONENT_TARGET_BRANCH" == "next-develop" ]]; then
        promote_branches "next-develop" "develop"
        export COMPONENT_TARGET_BRANCH=develop
    fi
else
    log "Skipping branch promotion (PROMOTE_BRANCHES='$PROMOTE_BRANCHES', PUSH_CHANGES='$PUSH_CHANGES')"
fi

if [[ "$PUSH_BINARY_ARCHIVES" = 1 || "$PUSH_CHANGES" = 1 ]]; then
    # Push the binary archives
    CHANGES_FILE="$(mktemp --tmpdir tmp.binary-archives-changes.XXXXXXXXXX)"
    add_to_cleanup "$CHANGES_FILE"
    if push_binary_archives "$CHANGES_FILE"; then
        "$SCRIPT_DIR/binary-archives-hook.sh" "$CHANGES_FILE"
    else
        ERRORS=1
    fi
else
    log "Skipping binary archives push (PUSH_BINARY_ARCHIVES='$PUSH_BINARY_ARCHIVES', PUSH_CHANGES='$PUSH_CHANGES')"
fi

exit "$ERRORS"
