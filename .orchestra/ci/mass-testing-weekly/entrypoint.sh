#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(realpath "$(dirname "${BASH_SOURCE[0]}")")

TIMESTAMP=$(date +%s)

# Install dependencies and the orchestra tool
sudo apt-get update
sudo apt-get install -y less nano vim

cd "$SCRIPT_DIR/../../.."
.orchestra/ci/install-dependencies.sh --full
pip3 -q install --user "git+https://github.com/revng/revng-orchestra.git@master"
export PATH="$HOME/.local/bin:$PATH"

# Copy user_options.yml and update
cp -a "$SCRIPT_DIR/user_options.yml" .orchestra/config/user_options.yml
orc update --no-config

# Run the progress poller, which will print the progress of mass-testing every
# hour
"$SCRIPT_DIR/progress_poller.sh" &
POLLER_PID=$!

# Run the actual mass-testing
RC=0
orc --quiet install mass-testing || RC=$?

kill -9 "$POLLER_PID"

# If mass-testing failed in any way, sleep forever. This is to allow manual
# intervention to recover the data (if present), since each run takes multiple
# days to finish
if [ "$RC" -ne 0 ]; then
  while true; do
    sleep 24h
  done
  exit "$RC"
fi

# Configure ssh for rsync-ing files to mass.rev.ng
mkdir -p ~/.ssh
chmod 700 ~/.ssh
cat > ~/.ssh/config <<EOF
Host *
    StrictHostKeyChecking no
    UserKnownHostsFile=/dev/null
EOF
eval "$(ssh-agent -s)"
base64 -d <<< "$PUSH_SSH_KEY" | tr -d '\r' | ssh-add -

# Copy just the report to the history subdirectory
rsync -qaz --stats \
  root/share/mass-testing-reports/all/ \
  "$RSYNC_TARGET:/history/$TIMESTAMP/"

# Fetch back via rsync all the 'main.db' files under '/history'. This is needed
# to create the file 'aggregated.json' which aggregates the historical data of
# mass-testing.
FILTER_FILE=$(mktemp)
TEMP_WORKDIR=$(mktemp -d)
TEMP_FILE=$(mktemp)
cat - > "$FILTER_FILE" <<EOF
R **
+ /*/
+ /*/main.db
- /***
EOF
rsync -qaz --filter ". $FILTER_FILE" "$RSYNC_TARGET:/history/" "$TEMP_WORKDIR"
"$SCRIPT_DIR/aggregate.py" "$TEMP_WORKDIR" "$TEMP_FILE"
chmod 644 "$TEMP_FILE"
rsync -qaz "$TEMP_FILE" "$RSYNC_TARGET:/history/aggregated.json"

# Copy the entirety of the mass-testing directory as the current execution
cat - > "$FILTER_FILE" <<EOF
R **
+ /inputs/***
+ /build/***
+ /report/***
- *
EOF

rsync -qaz --stats \
  --delay-updates \
  --delete-after \
  --filter ". $FILTER_FILE" \
  build/mass-testing/default/ \
  "$RSYNC_TARGET:/current/"
