#!/bin/bash

# $(1): destination
# $(2): path
# $(3): file name

echo "Downloading $3 from $2"
mkdir -p "$SOURCE_ARCHIVES"
trap "rm -f -- '$SOURCE_ARCHIVES/$3'" EXIT

if [ -e "$SOURCE_ARCHIVES/$3" ]; then
  echo "$3 already cached"
else
  curl -L "$2/$3" > "$SOURCE_ARCHIVES/$3"
fi

trap - EXIT;

echo "Copying $3 into $1"
cp "$SOURCE_ARCHIVES/$3" "$1/$3"
