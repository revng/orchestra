#!/bin/bash

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
# Optional parameters:
#
# BASE_USER_OPTIONS_YML:
#   user_options.yml is initialized to this value.
#   %GITLAB_ROOT% is replaced with the base URL of the Gitlab instance.
# COMPONENT_TARGET_BRANCH:
#   branch name to try first when checking out component sources
# PUSH_CHANGES:
#   if != 1 do not push binary archives and do not promote next-* branches
# PUSH_BINARY_ARCHIVE_EMAIL: used as author's email in binary archive commit
# PUSH_BINARY_ARCHIVE_NAME: used as author's name in binary archive commit
# SSH_PRIVATE_KEY: private key used to push binary archives
# REVNG_ORCHESTRA_URL: orchestra git repo URL (must be git+ssh:// or git+https://)

set -e
set -x

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ORCHESTRA_ROOT="$(realpath "$DIR/../..")"
ORCHESTRA_DOTDIR="$ORCHESTRA_ROOT/.orchestra"
USER_OPTIONS="$ORCHESTRA_DOTDIR/config/user_options.yml"

function log() {
    echo "$1" > /dev/stderr
}

PUSH_BINARY_ARCHIVE_EMAIL="${PUSH_BINARY_ARCHIVE_EMAIL:-sysadmin@rev.ng}"
PUSH_BINARY_ARCHIVE_NAME="${PUSH_BINARY_ARCHIVE_NAME:-rev.ng CI}"

cd "$DIR"

# Install dependencies
"$DIR/install-dependencies.sh"

#
# Register deploy key, if any
#
set +x
if test -n "$SSH_PRIVATE_KEY"; then
    eval "$(ssh-agent -s)"
    echo "$SSH_PRIVATE_KEY" | tr -d '\r' | ssh-add -
    unset SSH_PRIVATE_KEY
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh

    # Disable checking the host key
    if ! test -e ~/.ssh/config; then
        cat > ~/.ssh/config <<EOF
Host *
    StrictHostKeyChecking no
    UserKnownHostsFile=/dev/null
EOF
    fi

    # Change orchestra remote to ssh if we were given the URL
    if [[ -n "$ORCHESTRA_CONFIG_REPO_SSH_URL" ]]; then
        git -C "$ORCHESTRA_ROOT" remote set-url origin "$ORCHESTRA_CONFIG_REPO_SSH_URL"
    fi
fi
set -x

#
# Install orchestra
#
if test -n "$REVNG_ORCHESTRA_URL"; then
    # COMPONENT_TARGET_BRANCH is not quoted on purpose -- if empty it has to be ignored instead of being expanded to
    # and empty string
    for REVNG_ORCHESTRA_TARGET_BRANCH in $COMPONENT_TARGET_BRANCH next-develop develop next-master master; do
        if pip3 install --user "$REVNG_ORCHESTRA_URL@$REVNG_ORCHESTRA_TARGET_BRANCH"; then
            break
        fi
    done
else
    pip3 install --user revng-orchestra
fi

# Make sure we can run orchestra
export PATH="$HOME/.local/bin:$PATH"
which orc

#
# Prepare the user_options.yml file
#
if test -e "$USER_OPTIONS"; then
    log "$USER_OPTIONS already exists!"
    exit 1
fi

REMOTE="$(git remote get-url origin | sed 's|^\([^:]*:\)\([^/]\)|\1/\2|')"
GITLAB_ROOT="$(dirname "$(dirname "$REMOTE")")"
echo "${BASE_USER_OPTIONS_YML//\%GITLAB_ROOT\%/$GITLAB_ROOT}" > "$USER_OPTIONS"

# Register target components
if test -n "$TARGET_COMPONENTS_URL"; then
    # Add components by repository URL
    for TARGET_COMPONENT_URL in $TARGET_COMPONENTS_URL; do
        NEW_COMPONENT="$(orc components --repository-url "$TARGET_COMPONENT_URL" \
                         | grep '^Component' \
                         | cut -d' ' -f2)"
        if test -z "$NEW_COMPONENT"; then
            log "Warning: ignoring URL $TARGET_COMPONENT_URL since it doesn't "\
                "match any component"
        else
            TARGET_COMPONENTS="$NEW_COMPONENT $TARGET_COMPONENTS"
        fi
    done
fi

if test -z "$TARGET_COMPONENTS"; then
    log "Nothing to do!"
    exit 1
fi

# Register components to build from source
cat >> "$USER_OPTIONS" <<EOF
#@overlay/replace
build_from_source:
EOF
for TARGET_COMPONENT in $TARGET_COMPONENTS; do
    echo "  - $TARGET_COMPONENT" >> "$USER_OPTIONS"
done

# Build branches list
cat >> "$USER_OPTIONS" <<EOF
#@overlay/replace
branches:
EOF

if [[ -n "$COMPONENT_TARGET_BRANCH" ]] \
    && ! [[ "$COMPONENT_TARGET_BRANCH" =~ ^(next-develop|develop|next-master|master)$ ]]; then

    echo "  - $COMPONENT_TARGET_BRANCH" >> "$USER_OPTIONS"
    if test "${COMPONENT_TARGET_BRANCH:0:5}" == "next-"; then
        echo "  - ${COMPONENT_TARGET_BRANCH:5}" >> "$USER_OPTIONS"
    fi
fi

cat >> "$USER_OPTIONS" <<EOF
  - next-develop
  - develop
  - next-master
  - master
EOF

# Print debug information
cat "$USER_OPTIONS"
find ..

orc update --no-config

# Print debugging information
# Full dependency graph
orc graph -b
# Solved dependency graph for the target component
orc graph --solved -b "$TARGET_COMPONENT"
# Information about the components
orc components --hashes --deps
# Binary archives commit
for BINARY_ARCHIVE_PATH in $(orc ls --binary-archives); do
    echo "Commit for $BINARY_ARCHIVE_PATH: "\
           "$(git -C "$BINARY_ARCHIVE_PATH" rev-parse HEAD)"
done

#
# Actually run the build
#
RESULT=0
for TARGET_COMPONENT in $TARGET_COMPONENTS; do
    if ! orc --quiet install -b --test --create-binary-archives "$TARGET_COMPONENT"; then
        RESULT=1
        break
    fi
done

if test "$PUSH_CHANGES" = 1; then
    #
    # Promote `next-*` branches to `*`
    #
    if test "$RESULT" -eq 0; then

        # Clone all the components having branch next-*
        for COMPONENT in $(orc components --branch 'next-*' \
                | grep '^Component' \
                | awk '{ print $2 }'); do
            # TODO: find a more robust way to clone if not already cloned
            if ! test -d "$ORCHESTRA_ROOT/sources/$COMPONENT"; then
                orc clone "$COMPONENT"
            fi
        done

        # Promote next-* to *.
        # We also promote orchestra config because fix-binary-archive-symlinks
        # uses the current branch name
        for SOURCE_PATH in $(orc ls --git-sources) "$ORCHESTRA_ROOT"; do
            if test -e "$SOURCE_PATH/.git"; then
                cd "$SOURCE_PATH"
                BRANCH="$(git rev-parse --abbrev-ref HEAD)"
                if test "${BRANCH:0:5}" == "next-"; then
                    PUSH_TO="${BRANCH:5}"
                    git branch -d "$PUSH_TO" || true
                    git checkout -b "$PUSH_TO" "$BRANCH"
                    git push origin "$PUSH_TO"
                fi
                cd -
            fi
        done

        orc fix-binary-archives-symlinks
    fi

    # Ensure we have git lfs
    git lfs >& /dev/null

    # Remove old binary archives
    orc binary-archives clean

    #
    # Push to binary archives
    #
    for BINARY_ARCHIVE_PATH in $(orc ls --binary-archives); do

        cd "$BINARY_ARCHIVE_PATH"

        git config user.email "$PUSH_BINARY_ARCHIVE_EMAIL"
        git config user.name "$PUSH_BINARY_ARCHIVE_NAME"

        if ! test -e .gitattributes; then
            git lfs track "*.tar.gz"
            git add .gitattributes
            git commit -m'Initialize .gitattributes'
        fi

        ls -lh
        git add .

        if ! git diff --cached --quiet; then
            git commit -m'Automatic binary archives'
            git status
            git stash
            GIT_LFS_SKIP_SMUDGE=1 git fetch
            GIT_LFS_SKIP_SMUDGE=1 git rebase -Xtheirs origin/master

            git config --add lfs.dialtimeout 300
            git config --add lfs.tlstimeout 300
            git config --add lfs.activitytimeout 300
            git config --add lfs.keepalive 300
            git push
            git lfs push origin master
        else
            log "No changes to push for $BINARY_ARCHIVE_PATH"
        fi

    done

    exit "$RESULT"

else
    echo "PUSH_CHANGES != 1, exiting without pushing changes"
    exit $RESULT
fi
