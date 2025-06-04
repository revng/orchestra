#!/usr/bin/env bash
set -euo pipefail

# Binary archives hooks script
# This script is run by ci-run.sh at the end **if** there have been files
# pushed to the binary archives. The purpose of this script is to run some
# operations related to the new files pushed onto the binary-archives; in
# particular:
# * Pushing the revng-distributable* tarballs to S3
# * Building a new docker image
# * If `PUSH_HOOK_SCRIPT` is present, `eval`-ing it
#
# Usage ./binary-archives-hook.sh CHANGES_FILE
#
# CHANGES_FILE:
#   File containing the list of changed files in the binary archives, each line
#   is a different file path
#
# Mandatory environment variables:
#
# COMPONENT_TARGET_BRANCH: target branch the CI has been triggered against
#
# BINARY_ARCHIVES_S3CMD_CONFIG:
#   This variable will contain a valid configuration for s3cmd that allows
#   PUT-ing and DELETE-ing object from S3
# BINARY_ARCHIVES_S3_PATH:
#   Prefix path where revng-distributable files will be copied to
#   example: s3://<bucket name>/this/is/a/prefix/
#
# PODMAN_REGISTRY_USER, PODMAN_REGISTRY_PASSWORD:
#   Credentials to use to upload a revng-distributable image to docker hub
# PODMAN_IMAGE_TARGET:
#   The path where the revng-distributable image will be uploaded to
#
# Optional environment variables:
#
# BINARY_ARCHIVES_HOOKS_FORCE:
#   If set to '1' the hooks are going to be run regardless if there have been
#   changes to the binary archives
# BINARY_ARCHIVES_HOOKS_SKIP:
#   If set to '1' the hooks are not going to be run, this script will exit
#   without doing anything
# PUSH_HOOK_SCRIPT:
#   If present, this script will be `eval`-ed in a subshell. Useful to
#   implement additional logic while maintaining orchestra agnostic.

if [[ "${BINARY_ARCHIVES_HOOKS_SKIP:-}" -eq 1 ]]; then
    exit 0
fi

SCRIPT_DIR=$(realpath "$(dirname "${BASH_SOURCE[0]}")")
CHANGES_FILE="$1"
ORCHESTRA_DOTDIR="$(realpath "$SCRIPT_DIR/../../.orchestra")"

BRANCH="$COMPONENT_TARGET_BRANCH"
S3_CONF_FILE=$(mktemp --tmpdir tmp.s3cmd-credentials-XXXXXXXXXX)
function cleanup() {
    rm -f "$S3_CONF_FILE"
}
trap cleanup EXIT


REDIST_PATHS=()
while IFS= read -r PATH_CHANGE; do
    if [[ "$PATH_CHANGE" = 'public/linux-x86-64/revng-distributable/default/'* || \
          "$PATH_CHANGE" = 'public/linux-x86-64/revng-distributable-public-demo/default/'* ]]; then
        REDIST_PATHS+=("$PATH_CHANGE")
    fi
done < "$CHANGES_FILE"

if [[ "${#REDIST_PATHS[@]}" -gt 0 || "${BINARY_ARCHIVES_HOOKS_FORCE:-}" -eq 1 ]]; then
    #
    # S3 sync of binary archives
    #

    BINARY_ARCHIVES_BASE="$ORCHESTRA_DOTDIR/binary-archives"
    cat - > "$S3_CONF_FILE" <<EOF
[default]
# Basic config
use_https = True
check_ssl_certificate = True

# Do not dereference symlinks
follow_symlinks = False

# Tweak multipart upload (only do if >1GB)
enable_multipart = True
multipart_chunk_size_mb = 1024

# Do not set metadata with unix permissions
preserve_attrs = False

# When sync-ing, remove files that are only present in S3
delete_removed = True
delete_after = True

# Logging
verbosity = ERROR

$BINARY_ARCHIVES_S3CMD_CONFIG
EOF

    for REDIST_PATH in "${REDIST_PATHS[@]}"; do
        FULL_REDIST_PATH="$BINARY_ARCHIVES_BASE/$REDIST_PATH"
        if [ -h "$FULL_REDIST_PATH" ]; then
            TEMP_FILE=$(mktemp)
            readlink "$FULL_REDIST_PATH" > "$TEMP_FILE"
            s3cmd put --config="$S3_CONF_FILE" --acl-public \
                "$TEMP_FILE" \
                "$BINARY_ARCHIVES_S3_PATH/$REDIST_PATH"
            rm "$TEMP_FILE"
        elif [ -f "$FULL_REDIST_PATH" ]; then
            pushd "$(dirname "$FULL_REDIST_PATH")" &> /dev/null
            git lfs pull -I "$(basename "$FULL_REDIST_PATH")"
            popd &> /dev/null
            s3cmd put --config="$S3_CONF_FILE" --acl-public \
                "$FULL_REDIST_PATH" \
                "$BINARY_ARCHIVES_S3_PATH/$REDIST_PATH"
        fi
    done

    # Also remove files which have been deleted in the meantime
    s3cmd --config="$S3_CONF_FILE" ls --recursive "$BINARY_ARCHIVES_S3_PATH" | \
        awk '{ print $4 }' | \
        while IFS= read -r OBJECT_PATH; do
            if [ ! -f "$BINARY_ARCHIVES_BASE/${OBJECT_PATH/#$BINARY_ARCHIVES_S3_PATH/}" ]; then
                s3cmd --config="$S3_CONF_FILE" del "$OBJECT_PATH"
            fi
        done

    #
    # Build docker image
    #

    LOCAL_IMAGE="localhost/revng-image-$( (tr -dc a-z0-9 < /dev/urandom || true) | head -c 16)"
    TAR_FILE="$BINARY_ARCHIVES_BASE/public/linux-x86-64/revng-distributable-public-demo/default/$BRANCH.tar.xz"

    pushd "$(dirname "$TAR_FILE")" &> /dev/null
    git lfs pull -I "$(basename "$(realpath "$TAR_FILE")")"
    popd &> /dev/null

    # TODO: check again when upgrading to 24.04 if the 'sudo' can be dropped
    sudo -i "$ORCHESTRA_DOTDIR/support/docker-image/build.sh" "$LOCAL_IMAGE" "$TAR_FILE"
    sudo -i podman login -u "$PODMAN_REGISTRY_USER" \
        -p "$PODMAN_REGISTRY_PASSWORD" \
        "$(cut -d/ -f1 <<< "$PODMAN_IMAGE_TARGET")"
    sudo -i podman push "$LOCAL_IMAGE" "$PODMAN_IMAGE_TARGET:$BRANCH"
    if [ "$BRANCH" == "master" ]; then
        sudo -i podman push "$LOCAL_IMAGE" "$PODMAN_IMAGE_TARGET:latest"
    fi
fi

#
# Run the PUSH_HOOK_SCRIPT, if present
#

if [[ -n "${PUSH_HOOK_SCRIPT:-}" ]]; then
    ( eval "$PUSH_HOOK_SCRIPT" )
fi
