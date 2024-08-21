#!/usr/bin/env bash

set -euo pipefail

mkdir -p "${SOURCE_ARCHIVES}/python"

python \
    -m pip \
    --disable-pip-version-check \
    --no-python-version-warning \
    --exists-action w \
    download \
    --dest "${SOURCE_ARCHIVES}/python/"
    "$@"
