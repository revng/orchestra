#!/bin/bash

INTO="${SOURCE_DIR}"
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

echo "Extracting $URL into $INTO"

if [ -z "${ARCHIVE_FILENAME}" ]; then
  ARCHIVE_FILENAME="$(basename "$URL")"
fi

if [ ! -e "${SRC_ARCHIVE_DIR}/${ARCHIVE_FILENAME}" ]; then
    echo "Downloading source archive to ${SRC_ARCHIVE_DIR}/${ARCHIVE_FILENAME}"
    mkdir -p "$SRC_ARCHIVE_DIR"
    wget -O "${SRC_ARCHIVE_DIR}/${ARCHIVE_FILENAME}" "$URL"
else
    echo "$URL already downloaded in ${SRC_ARCHIVE_DIR}/${ARCHIVE_FILENAME}"
fi

mkdir -p "$INTO"
pushd "$INTO"
tar --extract --file "${SRC_ARCHIVE_DIR}/${ARCHIVE_FILENAME}" --strip-components=1
popd
