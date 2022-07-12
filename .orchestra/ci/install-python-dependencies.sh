#!/bin/bash

set -euo pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

user_flag="--user"
if [[ ! -z "${VIRTUAL_ENV:-}" ]]; then
    user_flag=""
fi

pip3 -q install $user_flag --upgrade -r "${DIR}/requirements.txt"
