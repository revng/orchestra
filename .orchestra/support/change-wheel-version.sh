#!/usr/bin/env bash
set -euo pipefail

INPUT_FILE="$1"
OUTPUT_DIR="$2"
NEW_VERSION="$3"

WORKDIR=$(mktemp -d --tmpdir tmp.change-wheel-version.XXXXXXXXXX)
trap 'rm -rf "$WORKDIR"' EXIT

cd "$WORKDIR"
unzip -q "$INPUT_FILE"
DISTINFO_DIR=$(find . -maxdepth 1 -type d -name '*.dist-info' -printf '%f')
OLD_VERSION=$(grep -Po '(?<=^Version: ).*$' "$DISTINFO_DIR/METADATA")
if [[ "$NEW_VERSION" = "+"* ]]; then
    NEW_VERSION="$OLD_VERSION${NEW_VERSION:1}"
fi

NEW_DISTINFO_DIR="${DISTINFO_DIR/"$OLD_VERSION"/"$NEW_VERSION"}"
mv "$DISTINFO_DIR" "$NEW_DISTINFO_DIR"

# Blanket-replace the version string in all the files
while IFS= read -r FILE; do
    sed -i "s;$OLD_VERSION;$NEW_VERSION;g" "$FILE"
done < <(find . -type f)

# Rebuild the RECORD file
NEW_RECORD_FILE="$NEW_DISTINFO_DIR/RECORD.new"
true > "$NEW_RECORD_FILE"
while IFS= read -r FILE; do
    if [[ "$FILE" != *".dist-info/RECORD"* ]]; then
        HASH=$(sha256sum "$FILE" | cut -d' ' -f1)
        LENGTH=$(wc -c "$FILE" | cut -d' ' -f1)
        echo "${FILE:2},sha256=${HASH},${LENGTH}" >> "$NEW_RECORD_FILE"
    fi
done < <(find . -type f)
echo "$NEW_DISTINFO_DIR/RECORD,," >> "$NEW_RECORD_FILE"
mv "$NEW_RECORD_FILE" "$NEW_DISTINFO_DIR/RECORD"
    
# Re-package the contents as a zip
INPUT_FILENAME=$(basename "$INPUT_FILE")
OUTPUT_FILE="$OUTPUT_DIR/${INPUT_FILENAME/"$OLD_VERSION"/"$NEW_VERSION"}"
zip -q9 -r "$OUTPUT_FILE" .

# Output filename
echo "$OUTPUT_FILE"
