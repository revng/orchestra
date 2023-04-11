#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

if [ "$EUID" -eq 0 ]; then
    "$SCRIPT_DIR/install-system-dependencies.sh"
else
    sudo "$SCRIPT_DIR/install-system-dependencies.sh"
fi
