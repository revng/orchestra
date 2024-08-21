#!/usr/bin/env bash

set -euo pipefail

python \
    -m pip \
    --disable-pip-version-check \
    --no-python-version-warning \
    install \
    --no-index \
    --compile \
    --no-warn-script-location \
    --find-links "${SOURCE_ARCHIVES}/python" \
    "$@"
