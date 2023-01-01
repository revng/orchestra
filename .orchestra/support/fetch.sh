#!/bin/bash
set -euo pipefail

SRC_ARCHIVE_DIR="${SOURCE_ARCHIVES:-}"
NO_COPY=0
URL=""
HASH=""
HASH_CMD=""

while [[ $# -gt 0 ]]; do
    key="$1"

    case $key in
        --src-archive-dir)
        SRC_ARCHIVE_DIR="$2"
        shift # past argument
        shift # past value
        ;;
        --save-as)
        ARCHIVE_FILENAME="$2"
        shift # past argument
        shift # past value
        ;;
        --hash)
        # Format is <hash type>-<hash>, for example sha512-0123456789abcdef...
        HASH_CMD=$(echo "$2" | cut -d'-' -f1)
        HASH=$(echo "$2" | cut -d'-' -f2)
        shift # past argument
        shift # past value
        ;;
        --no-copy)
        NO_COPY=1
        shift # past argument
        ;;
        --*)    # unknown option
        echo "Unknown option: $1" >&2
        exit 1
        ;;
        *)
        if [ -z "$URL" ]; then
            URL="$1"
        else
            echo "Only one url at a time may be specified" > /dev/stderr
            exit 1
        fi
        shift
        ;;
    esac
done

if [ -z "${ARCHIVE_FILENAME:-}" ]; then
  ARCHIVE_FILENAME="$(basename "$URL" | cut -d'#' -f1)"
fi

TMP_ARCHIVE_FILENAME="${ARCHIVE_FILENAME}.tmp"
TMP_ARCHIVE_PATH="${SRC_ARCHIVE_DIR}/${TMP_ARCHIVE_FILENAME}"
trap 'if [ -e "$TMP_ARCHIVE_PATH" ]; then rm "$TMP_ARCHIVE_PATH"; fi' INT QUIT TERM EXIT

if [ ! -e "${SRC_ARCHIVE_DIR}/${ARCHIVE_FILENAME}" ]; then
    echo "Downloading source archive to ${SRC_ARCHIVE_DIR}/${ARCHIVE_FILENAME}"
    mkdir -p "$SRC_ARCHIVE_DIR"
    wget --no-check-certificate -q -O "${SRC_ARCHIVE_DIR}/${TMP_ARCHIVE_FILENAME}" "$URL"
    if [[ -n "$HASH" && "$HASH_CMD" != "none" ]]; then
        if ! "$HASH_CMD"sum --quiet -c - <<< "${HASH} ${SRC_ARCHIVE_DIR}/${TMP_ARCHIVE_FILENAME}"; then
            echo "Downloaded file's hash does not match the provided one" > /dev/stderr
            exit 1
        fi
    fi
    mv "${SRC_ARCHIVE_DIR}/${TMP_ARCHIVE_FILENAME}" "${SRC_ARCHIVE_DIR}/${ARCHIVE_FILENAME}"
else
    echo "$URL already downloaded in ${SRC_ARCHIVE_DIR}/${ARCHIVE_FILENAME}"
fi

if [ "$NO_COPY" -eq 0 ]; then
    cp -a "${SRC_ARCHIVE_DIR}/${ARCHIVE_FILENAME}" .
fi

