#!/bin/bash

set -e
set -o pipefail

if [[ $# != 2 ]]; then
    echo "Usage: $0 <component> <root>"
    echo "Removes the files installed by <component>, relative to <root> path"
    exit 1
fi

if [[ ! -d "$2" ]]; then
    echo "Root '$2' does not exist or is not a directory"
    exit 1
fi

orchestra inspect component installed-files "$1" | while read f; do
    rm -f "$2/$f";
done
