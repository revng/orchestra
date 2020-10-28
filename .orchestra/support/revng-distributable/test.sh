#!/bin/bash

set -e
set -x

function test_ui() {
    ./revng ui "$@" &
    PID="$!"
    sleep 3;
    if test -d "/proc/$PID"; then
        xdotool \
            windowactivate --sync $(xdotool search --classname '.*revng.*') \
            key --clearmodifiers --delay 100 alt+F4 &
        wait "$PID"
    else
        return 1
    fi
}

TARGET="$1"
if test -e "$TARGET"; then
  cd "$TARGET"
fi

test_ui
ls root/share/revng/qa/tests/runtime/*/abi-enforced-for-decompilation/*.bc
test_ui root/share/revng/qa/tests/runtime/x86_64/abi-enforced-for-decompilation/calc.bc

./revng \
  lift \
  -g ll \
  root/share/revng/qa/tests/runtime/x86_64/compiled/calc \
  /tmp/calc.ll

./revng \
  opt \
  -S \
  --detect-abi \
  --isolate \
  --disable-enforce-abi-safety-checks \
  --enforce-abi \
  /tmp/calc.ll \
  -o /tmp/calc.for-decompilation.ll

test_ui /tmp/calc.for-decompilation.ll

./revng \
  translate \
  -i \
  root/share/revng/qa/tests/runtime/x86_64/compiled/calc \
  -o /tmp/calc.translated

/tmp/calc.translated '(+ 3 5)'
