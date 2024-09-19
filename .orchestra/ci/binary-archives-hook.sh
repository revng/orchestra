#!/bin/bash
set -euo pipefail

# Binary archives hooks script
# This script is run by ci-run.sh at the end **if** there have been files
# pushed to the binary archives.
#
# Mandatory parameters:
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
# Optional parameters:
#
# PUSH_HOOK_SCRIPT:
#   If present, this script will be `eval`-ed in a subshell. Useful to
#   implement additional logic while maintaining orchestra agnostic.

S3_CONF_FILE=$(mktemp --tmpdir tmp.s3cmd-credentials-XXXXXXXXXX)
DOCKER_CONTEXT=$(mktemp --tmpdir -d tmp.podman-context-XXXXXXXXXX)
function cleanup() {
    rm -f "$S3_CONF_FILE"
    rm -rf "$DOCKER_CONTEXT"
}
trap cleanup EXIT


REDIST_PATHS=()
for PATH_CHANGE in "${BINARY_ARCHIVES_PATH_CHANGES[@]}"; do
    if [[ "$PATH_CHANGE" = 'public/linux-x86-64/revng-distributable/default/'* || \
          "$PATH_CHANGE" = 'public/linux-x86-64/revng-distributable-public-demo/default/'* ]]; then
        REDIST_PATHS+=("$PATH_CHANGE")
    fi
done

if [ "${#REDIST_PATHS[@]}" -gt 0 ]; then
    #
    # S3 sync of binary archives
    #

    BINARY_ARCHIVES_BASE="$ORCHESTRA_DOTDIR/binary-archives"
    echo "$BINARY_ARCHIVES_S3CMD_CONFIG" > "$S3_CONF_FILE"

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

    # TODO: check again when upgrading to 24.04 if the 'sudo' can be dropped
    LOCAL_IMAGE="localhost/revng-image-$(tr -dc A-Za-z0-9 < /dev/urandom | head -c 16)"
    sudo -i podman build \
        -t "$LOCAL_IMAGE" \
        -f "$ORCHESTRA_DOTDIR/support/Dockerfile.binary-archives" \
        "$DOCKER_CONTEXT"
    sudo -i podman login -u "$PODMAN_REGISTRY_USER" \
        -p "$PODMAN_REGISTRY_PASSWORD" \
        "$(cut -d/ -f1 <<< "$PODMAN_IMAGE_TARGET")"
    sudo -i podman push "$LOCAL_IMAGE" "$PODMAN_IMAGE_TARGET"
fi


#
# Run the PUSH_HOOK_SCRIPT, if present
#

if [[ -n "${PUSH_HOOK_SCRIPT:-}" ]]; then
    ( eval "$PUSH_HOOK_SCRIPT" )
fi
