#!/usr/bin/env bash
set -euo pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

INTO=""
if test -d "${SOURCE_DIR-}"; then
    INTO="${SOURCE_DIR}"
fi
SRC_ARCHIVE_DIR="${SOURCE_ARCHIVES}"

POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    --into)
    INTO="$2"
    shift # past argument
    shift # past value
    ;;
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
    *)    # unknown option
    POSITIONAL+=("$1") # save it in an array for later
    shift # past argument
    ;;
esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters

URL="${POSITIONAL[0]}"

if test -z "$INTO"; then
    echo "No destination specified and SOURCE_DIR not set" > /dev/stderr
    exit 1
fi

echo "Extracting $URL into $INTO"

if [ -z "${ARCHIVE_FILENAME:-}" ]; then
  ARCHIVE_FILENAME="$(basename "$URL")"
fi

"$DIR"/fetch.sh --src-archive-dir "$SRC_ARCHIVE_DIR" --save-as "$ARCHIVE_FILENAME" --no-copy $URL

mkdir -p "$INTO"
pushd "$INTO" > /dev/null
tar --extract --file "${SRC_ARCHIVE_DIR}/${ARCHIVE_FILENAME}" --strip-components=1
popd > /dev/null
