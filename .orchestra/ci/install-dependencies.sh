#!/bin/bash

set -e

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

"$SCRIPT_DIR/install-system-dependencies.sh"
"$SCRIPT_DIR/install-python-dependencies.sh"
