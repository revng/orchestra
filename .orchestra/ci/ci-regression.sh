#!/usr/bin/env bash
set -euo pipefail

# rev.ng CI regression script
# This script is run after the `ci-run.sh` has run and has successfully
# promoted a next-develop branch to develop. The purpose of this script is to
# promote the develop branch to master. The prerequisites for this are:
# * Passing some form of regression (typically, `mass-testing-regression`)
# * If present, a downstream pipeline which is expected to trigger downstream
#   tests and finish successfully if those pass
# If the above happens then the develop branches are promoted to master
# (triggering binary archive hooks in the process) and, if present, the
# downstream pipeline is triggered again.
#
# Mandatory environment variables:
#
# REGRESSION_TARGET_COMPONENT: name of the orchestra target to build to test regression
# REVNG_ORCHESTRA_URL: orchestra git repo URL (must be git+ssh:// or git+https://)
#
# Optional environment variables:
#
# SSH_PRIVATE_KEY: private key used to push binary archives
# LFS_RETRIES: Number of times lfs pull/push operations are retried. Defaults to 3.

SCRIPT_DIR=$(realpath "$(dirname "${BASH_SOURCE[0]}")")
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

cd "$ORCHESTRA_REPO_DIR"
"$SCRIPT_DIR/install-dependencies.sh"
# TODO: remove this once install-dependencies does this itself
sudo apt-get -qq install --no-install-recommends --yes inkscape

# Install revng-orchestra
for REVNG_ORCHESTRA_TARGET_BRANCH in next-develop develop master; do
    if pip3 -q install --user "$REVNG_ORCHESTRA_URL@$REVNG_ORCHESTRA_TARGET_BRANCH"; then
        break
    fi
done

# Make sure we can run orchestra
export PATH="$HOME/.local/bin:$PATH"
command -v orc > /dev/null

# Load ssh key, if present
load_ssh_key

# Populate USER_OPTIONS
cat > "$USER_OPTIONS" <<EOF
$(get_user_options)

#@overlay/replace
branches:
  - develop
  - master

#@overlay/replace
build_from_source:
  - mass-testing-regression
EOF

# Print debug information
echo "User options:"
cat "$USER_OPTIONS"

# Update, this is needed here because 'pipeline_create' will run
# `orc ls --binary-archives`
orc update --no-config

# Start downstream pipeline, since it can take a while this and the run of
# the regression suite are started in parallel to optimize time
PIPELINE_ID=$(COMPONENT_TARGET_BRANCH=develop pipeline_create)

# Run regression suite
orc --quiet install \
    --discard-build-directories \
    --lfs-retries "$LFS_RETRIES" \
    -b mass-testing-regression

# Wait and check if the downstream pipeline has finished
pipeline_wait "$PIPELINE_ID"

#
# Promote develop to master and push
#
promote_branches develop master
export COMPONENT_TARGET_BRANCH=master
CHANGES_FILE="$(mktemp --tmpdir tmp.binary-archives-changes.XXXXXXXXXX)"
add_to_cleanup "$CHANGES_FILE"
push_binary_archives "$CHANGES_FILE"
"$SCRIPT_DIR/binary-archives-hook.sh" "$CHANGES_FILE"

#
# Run the downstream pipeline, if needed
#
pipeline_wait "$(pipeline_create)"
