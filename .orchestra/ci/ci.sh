#!/bin/bash

set -e
set -x

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

function log() {
    echo "$1" > /dev/stderr
}

PUSH_BINARY_ARCHIVE_EMAIL="${PUSH_BINARY_ARCHIVE_EMAIL:-sysadmin@rev.ng}"
PUSH_BINARY_ARCHIVE_NAME="${PUSH_BINARY_ARCHIVE_NAME:-rev.ng CI}"

cd "$DIR"

#
# Register deploy key, if any
#
set +x
if test -n "$SSH_PRIVATE_KEY"; then
    eval $(ssh-agent -s)
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
fi
set -x

#
# Detect target branch
#
BRANCH=""
if test -n "$PUSHED_REF"; then
    if [[ "$PUSHED_REF" = refs/heads/* ]]; then
        BRANCH="${PUSHED_REF#refs/heads/}"

        # Switch orchestra to that branch too, if it exists
        git fetch
        git checkout "$BRANCH" || true
    else
        log "PUSHED_REF ($PUSHED_REF) is not a branch, bailing out"
        exit 0
    fi
fi

#
# Install orchestra
#
if test -n "$REVNG_ORCHESTRA_URL"; then
    pip3 install --user "$REVNG_ORCHESTRA_URL"
else
    pip3 install --user revng-orchestra
fi

# Make sure we can run orchestra
export PATH="$HOME/.local/bin:$PATH"
which orc

#
# Prepare the user_options.yml file
#
if test -e ../config/user_options.yml; then
    log "user_options.yml already exists!"
    exit 1
fi

REMOTE="$(git remote get-url origin | sed 's|^\([^:]*:\)\([^/]\)|\1/\2|')"
GITLAB_ROOT="$(dirname $(dirname $REMOTE))"
echo "$BASE_USER_OPTIONS_YML" | sed "s|%GITLAB_ROOT%|$GITLAB_ROOT|g" > ../config/user_options.yml

# Register target components
if test -n "$TARGET_COMPONENTS_URL"; then
    # Add components by repository URL
    for TARGET_COMPONENT_URL in $TARGET_COMPONENTS_URL; do
        NEW_COMPONENT="$(orc components --repository-url "$TARGET_COMPONENT_URL" \
                         | grep '^Component' \
                         | cut -d' ' -f2)"
        if test -z "$NEW_COMPONENT"; then
            log "Warning: ignoring URL $TARGET_COMPONENT_URL since it doesn't match any component"
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
cat >> ../config/user_options.yml <<EOF
#@overlay/replace
build_from_source:
EOF
for TARGET_COMPONENT in $TARGET_COMPONENTS; do
    echo "  - $TARGET_COMPONENT" >> ../config/user_options.yml
done

# Build branches list
cat >> ../config/user_options.yml <<EOF
#@overlay/replace
branches:
EOF

if test -n "$BRANCH" && ! [[ "$BRANCH" =~ ^(next-develop|develop|next-master|master)$ ]]; then
    echo "  - $BRANCH" >> ../config/user_options.yml
    if test "${BRANCH:0:5}" == "next-"; then
        echo "  - ${BRANCH:5}" >> ../config/user_options.yml
    fi
fi

cat >> ../config/user_options.yml <<EOF
  - next-develop
  - develop
  - next-master
  - master
EOF

# Print debug information
cat ../config/user_options.yml
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
    echo "Commit for $BINARY_ARCHIVE_PATH:" "$(git -C "$BINARY_ARCHIVE_PATH" rev-parse HEAD)"
done

#
# Actually run the build
#
RESULT=0
for TARGET_COMPONENT in $TARGET_COMPONENTS; do
    if ! orc install -b --test --create-binary-archives "$TARGET_COMPONENT"; then
        RESULT=1
        break
    fi
done

#
# Promote `next-*` branches to `*`
#
if test "$RESULT" -eq 0; then

    # Clone all the components having branch next-*
    for COMPONENT in $(orc components --branch 'next-*' | grep '^Component' | awk '{ print $2 }'); do
        if ! test -d "sources/$COMPONENT"; then
           orc clone "$COMPONENT"
        fi
    done

    # Promote next-* to *
    for SOURCE_PATH in $(orc ls --git-sources); do
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

#
# Push to binary archives
#
for BINARY_ARCHIVE_PATH in $(orc ls --binary-archives); do

    cd "$BINARY_ARCHIVE_PATH"

    # Ensure we have git lfs
    git lfs >& /dev/null

    git config user.email "$PUSH_BINARY_ARCHIVE_EMAIL"
    git config user.name "$PUSH_BINARY_ARCHIVE_NAME"

    if ! test -e .gitattributes; then
        git lfs track "*.tar.gz"
        git add .gitattributes
        git commit -m'Initialize .gitattributes'
    fi

    ls -lh
    git add .

    # TODO: cleanup-binary-archives.sh

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
        log "Nothing new to push"
    fi

done

exit "$RESULT"
