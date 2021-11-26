#!/bin/bash

set -e
export QT_DEBUG_PLUGINS=1

function start_xvfb() {
    echo "Starting xvfb"
    export XAUTHORITY=/tmp/.Xauthority
    export DISPLAY=:99

    touch "$XAUTHORITY"
    Xvfb "$DISPLAY" -screen 0 1920x1080x24 -auth $XAUTHORITY -ac +extension GLX +render -noreset &
    XVFB_PID="$!"
    # TODO: find a way to reliably tell when Xvfb started up without using sleep (xprop?)
    # Wait for Xvfb to start up
    sleep 5

    fluxbox -sync &
    WM_PID="$!"
    # TODO: find a way to reliably tell when fluxbox started up without using sleep (wmctrl?)
    # Wait for the WM to start up
    sleep 5
}

function stop_xvfb() {
    echo "Stopping xvfb"
    kill -TERM "$WM_PID"
    wait "$WM_PID"
    kill -TERM "$XVFB_PID"
    wait "$XVFB_PID"
}

function kill_ui () {
    # Kills revng-ui and waits for its termination
    # $1: revng-ui PID
    local PID="$1"

    if [[ "$COLD_REVNG_KILL_METHOD" == "kill" ]]; then
        kill "$PID"
    elif [[ "$COLD_REVNG_KILL_METHOD" == "kill9" ]]; then
        kill -9 "$PID"
    elif [[ "$COLD_REVNG_KILL_METHOD" == "wmctrl" ]]; then
        wmctrl -v -c cold-revng || true
    else
        xdotool search cold-revng windowactivate --sync key --window 0 --clearmodifiers alt+F4
    fi
    wait "$PID" || true
}

function test_ui() {
    ./revng ui "$@" &
    PID="$!"
    sleep 10;
    if test -d "/proc/$PID"; then
        kill_ui "$PID"
    else
        return 1
    fi
}

TARGET="$1"
if test -e "$TARGET"; then
  cd "$TARGET"
fi

if [[ "$USE_XVFB" == 1 ]]; then
    start_xvfb
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

if [[ "$USE_XVFB" == 1 ]]; then
  stop_xvfb
fi
