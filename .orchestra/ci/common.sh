# shellcheck shell=bash disable=SC2034
set -euo pipefail

SCRIPT_DIR=$(realpath "$(dirname "${BASH_SOURCE[0]}")")
ORCHESTRA_REPO_DIR="$(realpath "$SCRIPT_DIR/../..")"
ORCHESTRA_DOTDIR="$ORCHESTRA_REPO_DIR/.orchestra"
USER_OPTIONS="$ORCHESTRA_DOTDIR/config/user_options.yml"
LFS_RETRIES="${LFS_RETRIES:-3}"

CLEANUP_PATHS=()
function add_to_cleanup() {
    CLEANUP_PATHS+=("$1")
}

function cleanup() {
    if [ "${#CLEANUP_PATHS[@]}" -eq 0 ]; then
        return 0
    fi
    rm -rf "${CLEANUP_PATHS[@]}"
}
trap cleanup EXIT

# Convenience function to load a base64-encoded SSH_PRIVATE_KEY via ssh-agent
function load_ssh_key() {
    if [ -z "${SSH_PRIVATE_KEY:-}" ]; then
        return 0
    fi
    eval "$(ssh-agent -s)"
    echo "$SSH_PRIVATE_KEY" | tr -d '\r' | ssh-add -
    unset SSH_PRIVATE_KEY
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh

    # Disable checking the host key
    if [ ! -e ~/.ssh/config ]; then
        cat > ~/.ssh/config <<EOF
Host *
    StrictHostKeyChecking no
    UserKnownHostsFile=/dev/null
EOF
    fi
}


# When called, it will promote the OLD_BRANCH to NEW_BRANCH for all orchestra
# components that have a git repo
function promote_branches() {
    local OLD_BRANCH="$1"
    local NEW_BRANCH="$2"

    # Clone all the components installed during this run that have a next-* branch
    # We have to clone them explicitly because they might have been installed from
    # binary archives and we need the repo to perform branch promotion
    orc components --installed --json --branch "$OLD_BRANCH" | jq -r ".[].name" | \
    while IFS= read -r COMPONENT; do
        log "Cloning $COMPONENT"
        orc clone --no-force "$COMPONENT"
    done

    # Promote OLD_BRANCH to NEW_BRANCH.
    local SOURCE_PATH
    for SOURCE_PATH in $(orc ls --git-sources) "$ORCHESTRA_REPO_DIR"; do
        if [ ! -e "$SOURCE_PATH/.git" ]; then
            continue
        fi

        pushd "$SOURCE_PATH" &> /dev/null
        if [ "$(git rev-parse --abbrev-ref HEAD)" == "$OLD_BRANCH" ]; then
            git checkout -B "$NEW_BRANCH" "$OLD_BRANCH"
            git push --force origin "$NEW_BRANCH"
        fi
        popd &> /dev/null
    done

    orc symlink-binary-archives "${NEW_BRANCH////-}"
}

# This function takes care of pushing all the binary archives, retrying a few
# times for lfs and writing a list of changed files to the supplied first
# parameter.
#
# Mandatory parameters:
#
# 1:
#   File where this function will write the list of changed files in the binary
#   archives, each line is a different file path
# COMPONENT_TARGET_BRANCH: the branch which the CI has been run against
#
# Optional parameters:
#
# PUSH_BINARY_ARCHIVE_EMAIL: used as author's email in binary archive commit
# PUSH_BINARY_ARCHIVE_NAME: used as author's name in binary archive commit
function push_binary_archives() {
    local CHANGES_FILE="$1"

    # Ensure we have git lfs
    git lfs --version &> /dev/null

    # Remove old binary archives
    orc binary-archives clean

    #
    # Push to binary archives
    #
    local BINARY_ARCHIVE_PATH
    for BINARY_ARCHIVE_PATH in $(orc ls --binary-archives); do
        cd "$BINARY_ARCHIVE_PATH"

        git config user.email "${PUSH_BINARY_ARCHIVE_EMAIL:-sysadmin@rev.ng}"
        git config user.name "${PUSH_BINARY_ARCHIVE_NAME:-rev.ng CI}"

        # Ensure we track the correct files
        git lfs track "*.tar.*"
        git add .gitattributes
        if ! git diff --staged --exit-code -- .gitattributes > /dev/null; then
            git commit -m'Initialize .gitattributes'
        fi

        ls -lh
        git add .

        if ! git diff --cached --quiet; then
            local COMMIT_MSG
            COMMIT_MSG="Automatic binary archives

ORCHESTRA_CONFIG_COMMIT=$(git -C "$ORCHESTRA_REPO_DIR" rev-parse --short HEAD || true)
ORCHESTRA_CONFIG_BRANCH=$(git -C "$ORCHESTRA_REPO_DIR" name-rev --name-only HEAD || true)
COMPONENT_TARGET_BRANCH=$COMPONENT_TARGET_BRANCH"

            git commit -m "$COMMIT_MSG"
            git status
            git stash
            GIT_LFS_SKIP_SMUDGE=1 git fetch
            GIT_LFS_SKIP_SMUDGE=1 git rebase -Xtheirs origin/master

            git config --add lfs.dialtimeout 300
            git config --add lfs.tlstimeout 300
            git config --add lfs.activitytimeout 300
            git config --add lfs.keepalive 300
            git push

            local LFS_RETRY_WAIT=5
            local LFS_ERRORS=1
            local TRIES=0
            while [[ "$TRIES" -lt "$LFS_RETRIES" ]]; do
                if git lfs push origin master; then
                    LFS_ERRORS=0
                    break
                fi
                TRIES=$((TRIES + 1))

                if [[ "$TRIES" -lt "$LFS_RETRIES" ]]; then
                    log_err "git lfs push failed, waiting $LFS_RETRY_WAIT seconds before retrying"
                    sleep "$LFS_RETRY_WAIT"
                    LFS_RETRY_WAIT=$((LFS_RETRY_WAIT * 2))
                fi
            done

            if [[ "$LFS_ERRORS" != 0 ]]; then
                log_err "git lfs push failed $TRIES times, giving up"
                return 1
            else
                local BINARY_ARCHIVE_NAME
                BINARY_ARCHIVE_NAME=$(basename "$BINARY_ARCHIVE_PATH")
                git diff --diff-filter=AMR --name-only HEAD^..HEAD | \
                while IFS= read -r path; do
                    echo "$BINARY_ARCHIVE_NAME/$path" >> "$CHANGES_FILE"
                done
            fi
        else
            log "No changes to push for $BINARY_ARCHIVE_PATH"
        fi
    done
}


# Pipeline creation
# This function's responsibility is to trigger the execution of a pipeline of a
# generic downstream project. The resulting ID is printed to stdout or a
# non-zero return code is returned
#
# Mandatory parameters:
#
# COMPONENT_TARGET_BRANCH: target branch the CI has been triggered against
#
# Optional parameters:
#
# DOWNSTREAM_PROJECT_URL:
#   The base URL that will be used to create a pipeline for the project, if
#   missing this function will exit without any output
# DOWNSTREAM_PROJECT_TARGET_BRANCH:
#   The target branch to use for the pipeline, defaults to 'master'
# BINARY_ARCHIVES_HOOKS_FORCE:
#   If set to '1' the hooks are going to be run regardless if there have been
#   changes to the binary archives
function pipeline_create() {
    if [ -z "${DOWNSTREAM_PROJECT_URL:-}" ]; then
        return 0
    fi

    local POST_VARIABLES='{'
    POST_VARIABLES+="\"COMPONENT_TARGET_BRANCH\": \"$COMPONENT_TARGET_BRANCH\","
    for BINARY_ARCHIVE_PATH in $(orc ls --binary-archives); do
        local BINARY_ARCHIVE_NAME VARIABLE_NAME VARIABLE_VALUE VARIABLE_ENTRY
        BINARY_ARCHIVE_NAME=$(basename "$BINARY_ARCHIVE_PATH")
        VARIABLE_NAME="BINARY_ARCHIVES_${BINARY_ARCHIVE_NAME@U}_HASH"
        VARIABLE_VALUE=$(git -C "$BINARY_ARCHIVE_PATH" rev-parse HEAD)
        POST_VARIABLES+="\"$VARIABLE_NAME\": \"$VARIABLE_VALUE\","
    done
    if [ "$COMPONENT_TARGET_BRANCH" != "master" ]; then
        POST_VARIABLES+="\"CI_NOPUSH\": \"1\","
    fi
    # Remove trailing `,` and add a trailing `}`
    POST_VARIABLES="${POST_VARIABLES%,}}"
    local PIPELINE_BRANCH="${DOWNSTREAM_PROJECT_TARGET_BRANCH:-master}"

    local REQ_OUTPUT REQ_CODE
    REQ_OUTPUT=$(mktemp)
    REQ_CODE=$(mktemp)
    add_to_cleanup "$REQ_OUTPUT"
    add_to_cleanup "$REQ_CODE"

    local RC=0
    # TODO: use `--write-out '%output{...}'` with curl > 8.3.0
    curl -X POST -s -o "$REQ_OUTPUT" \
        --write-out '%{http_code}' \
        -H 'Content-Type: application/json' \
        --data "{\"token\": \"$CI_JOB_TOKEN\", \"ref\": \"$PIPELINE_BRANCH\", \"variables\": $POST_VARIABLES}" \
        "$DOWNSTREAM_PROJECT_URL/trigger/pipeline" > "$REQ_CODE" || RC=$?

    if [[ $RC -ne 0 || $(cat "$REQ_CODE") -ne 200 || $(jq .error "$REQ_OUTPUT") != "null" ]]; then
        return 1
    fi

    jq -r .id "$REQ_OUTPUT"
}


# This function will wait for the specified pipeline ID to finish
#
# Mandatory parameters:
#
# 1:
#   The ID of the pipeline execution, as returned by `pipeline_create`
# DOWNSTREAM_PROJECT_URL:
#   The base URL that will be used to create a pipeline for the project
function pipeline_wait() {
    local PIPELINE_ID="$1"

    # `pipeline_create` can sometimes return an empty output (e.g.
    # DOWNSTREAM_PROJECT_URL is not defined). In these cases return
    # successfully without doing anything
    if [ -z "$PIPELINE_ID" ]; then
        return 0
    fi

    local REQ_OUTPUT REQ_CODE
    REQ_OUTPUT=$(mktemp)
    REQ_CODE=$(mktemp)
    add_to_cleanup "$REQ_OUTPUT"
    add_to_cleanup "$REQ_CODE"

    while true; do
        # NOTE:
        #   gitlab does not allow CI job tokens to GET a pipeline, however it
        #   does allow changing the name of a previously-created pipeline,
        #   which has the side effect of also returning the pipeline's status.
        #   This is a semi-hack, but it works
        local RC=0
        curl -X PUT -s -o "$REQ_OUTPUT" \
            --write-out '%{http_code}' \
            --data "job_token=$CI_JOB_TOKEN" \
            --data "name=orchestra-trigger-from-ci" \
            "$DOWNSTREAM_PROJECT_URL/pipelines/$PIPELINE_ID/metadata" > "$REQ_CODE" || RC=$?

        if [[ $RC -ne 0 || $(cat "$REQ_CODE") -ne 200 || $(jq .error "$REQ_OUTPUT") != "null" ]]; then
            return 1
        fi

        STATUS=$(jq -r .status "$REQ_OUTPUT")
        if [[ "$STATUS" = "failed" ]]; then
            return 1
        elif [[ "$STATUS" = "success" ]]; then
            return 0
        else
            # If here the pipeline has not yet failed nor succeeded, sleep for a bit
            sleep 10
        fi
    done
}
