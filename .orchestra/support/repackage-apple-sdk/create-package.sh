#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 Xcode_9.xip"
    exit 1
fi

INITIAL_DIR="$PWD"
INPUT_FILE="$(readlink -f $1)"
OUTPUT_FILE="$INPUT_FILE-MacOSX.sdk.tar.gz"

WORKING_DIR="$INPUT_FILE.extracted"
mkdir "$WORKING_DIR"
cd "$WORKING_DIR"

echo "Compiling pbzx"
gcc "$DIR/pbzx.c" "$DIR/decompress.c" -llzma -o pbzx

echo "Extracting Content from $INPUT_FILE"
7z x "$INPUT_FILE"

test -e Content

echo "Unpacking Content"
( ./pbzx Content | cpio -i ) || true

cd "$WORKING_DIR/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/"
ln -s System/Library/Frameworks Library
ln -s usr Developer

# This file conflicts with other toolchains
rm -f usr/lib/crt1.o

cd ..

echo "Creating the $1-MacOSX.sdk.tar.gz archive"
tar ca --owner=0 --group=0 -f "$OUTPUT_FILE" MacOSX.sdk

cd "$INITIAL_DIR"
cd ..

echo "Removing temporary directory"
rm -rf "$WORKING_DIR"
