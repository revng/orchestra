#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="build/mass-testing/default"
while true; do
    sleep 1h

    if [[ ( ! -d "$BASE_DIR/inputs" ) || ( ! -d "$BASE_DIR/build" ) ]]; then
        continue
    fi

    TOTAL=$(find "$BASE_DIR/inputs" -type f | wc -l)
    COUNT=$(find "$BASE_DIR/build" -name test-harness.json | wc -l)
    PERCENT=$(python3 -c "print('{:03.2f}'.format($COUNT * 100 / $TOTAL))")

    echo '------- MASS TESTING PROGRESS -------'
    echo "Timestamp:  $(date --iso-8601=seconds)"
    echo "Inputs processed: $(printf %10d "${COUNT}") ($PERCENT%)"
    echo "Total:            $(printf %10d "${TOTAL}")"
    echo '-------------------------------------'
done
