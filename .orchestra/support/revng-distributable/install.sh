#!/bin/bash

set -euo pipefail

if test "$#" -lt 2; then
    echo "Usage: $0 [COMPONENT_NAME] [DEPENDENCY [DEPENDENCY ...]]" > /dev/stderr
    exit 1
fi

COMPONENT_NAME="$1"
shift

DISTRIBUTABLE_PATH="${DESTDIR}${ORCHESTRA_ROOT}/${COMPONENT_NAME}"

echo "Copying root"
rm -rf "${DISTRIBUTABLE_PATH}/root"
mkdir -p "${DISTRIBUTABLE_PATH}/root"

cd "$ORCHESTRA_ROOT"

for component in "$@"; do
  echo "$component"
  orc inspect component dependencies --installed --runtime "$component"
done | sort | uniq | \
while IFS= read -r component; do
  orc inspect component installed-files "${component}"
done | \
grep -vP '^include/(?!revng/PipelineC/(Prototypes|ForwardDeclarationsC)\.h)' | \
grep -vP '^share/doc/(?!revng)' | \
grep -vE \
  -e 'cmake' \
  -e 'node_modules' \
  -e 'node_cache' \
  -e 'man/' \
  -e '^lib64/pkgconfig/' \
  -e '^share/aclocal/' \
  -e '^share/bash-completion/' \
  -e '^share/gcc-data/' \
  -e '^share/orchestra/save_for_later' \
  -e '^share/qemu/' \
  -e '^share/revng/test/' \
  -e '^share/terminfo/' | \
rsync \
  --archive \
  --quiet \
  --files-from=- \
  "$ORCHESTRA_ROOT/." \
  "${DISTRIBUTABLE_PATH}/root/."

cd "${DISTRIBUTABLE_PATH}"

echo "Creating environment"
cp -a "$ORCHESTRA_DOTDIR/support/revng-distributable/environment" environment

# shellcheck disable=SC2094
{
  orchestra environment | grep -E "^export (PATH|REVNG_TRANSLATE_LDFLAGS|LLVM_SYMBOLIZER_PATH|AWS_EC2_METADATA_DISABLED|HARD_|RPATH_PLACEHOLDER)"
  cat <<EOF
unset ORCHESTRA_DOTDIR
unset ORCHESTRA_ROOT
EOF
} >> environment


echo "Copying README.md"
cp -a "$ORCHESTRA_DOTDIR/support/revng-distributable/README.md" .

echo "Copying revng"
cp -a "$ORCHESTRA_DOTDIR/support/revng-distributable/revng" revng


cd "${DISTRIBUTABLE_PATH}/root"

echo "Copying revng-distributable scripts"
cp -a \
  "$ORCHESTRA_DOTDIR/support/revng-distributable/revng-update" \
  "$ORCHESTRA_DOTDIR/support/revng-distributable/revng-system-info" \
  libexec/revng/

echo "revng-distributable updater info"
mkdir -p share/revng-distributable
echo 1 > share/revng-distributable/version

cat > share/revng-distributable/post-update <<eof
#!/usr/bin/env bash
set -e
./revng --help >& /dev/null
./revng lift --help >& /dev/null
echo "Update successful!"
eof
chmod +x share/revng-distributable/post-update

ln -s lib64 lib

echo "Stripping components"
cat \
  <(find 'share/orchestra' -type f -name '*.idx' ! -name '*revng*' -exec cat {} \;) \
  <(find 'libexec/revng' -type f) | \
while read -r FILE; do
  if [ -f "$FILE" ] && file "$FILE" | grep -qE 'ELF.*x86-64.*(shared|dynamic).*not stripped'; then
    echo "Stripping $FILE"
    strip "$FILE"
  fi
done

echo "Fix .idx"
ALL_FILES=$(find . -type f | sed 's;^\.\/;;g' | sort)
TMP_IDX=$(mktemp -p "${BUILD_DIR}")
# For each .idx remove from it any file that is missing from our stripped root
for IDX in share/orchestra/*.idx; do
  comm -12 <(sort "$IDX") <(echo "$ALL_FILES") > "$TMP_IDX"
  if [ "$(wc -l < "$TMP_IDX")" -gt 3 ]; then
    # If there are files remaining replace the idx with the filtered one
    sort "$TMP_IDX" > "$IDX"
  else
    # We removed all the files of the component, remove its files entirely
    rm -f "$IDX" "${IDX//.idx/.license}" "${IDX//.idx/.json}"
  fi
done
rm "$TMP_IDX"

# Copying x86_64-calc for smoke tests
TEST_BINARY=$(echo "$ORCHESTRA_ROOT/share/revng/test/tests/runtime/calc-x86-64-static-revng-qa.compiled-with-debug-info-"*)
cp -a "$TEST_BINARY" share/revng/calc-x86-64-static

echo "Generating checksums"
cd "${DISTRIBUTABLE_PATH}"
find root -type f -print0 | xargs -0 -P"$JOBS" -n100 sha256sum > checksums.sha256
sha256sum README.md environment revng >> checksums.sha256

echo "Final cleanup"
cd "${DISTRIBUTABLE_PATH}/.."
find . -not -type d -not -path './'"$COMPONENT_NAME"'/*' -delete
find . -type d -empty -delete

if [ "$RUN_TESTS" -eq 1 ]; then
  TEST_CMD=(
    ./revng
    graphql
    --analyses-list=revng-initial-auto-analysis
    --analyses-list=revng-c-initial-auto-analysis
    --produce-artifacts
    "$TEST_BINARY"
  )

  # Orchestra adds quite a few environment variables, which we want to avoid to use when doing self-test
  # In order to launch self-test with as few environment variables as possible we:
  # * use `env -i` to start with no environment variables
  # * use `bash --login` to restore the ones provided at login (e.g. PATH)
  env -i -C "${DISTRIBUTABLE_PATH}" bash --login -c "set -e; ${TEST_CMD[*]}"
fi
