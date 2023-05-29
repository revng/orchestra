#!/bin/bash
set -euo pipefail

echo "Copying root"
rm -rf "${DESTDIR}${ORCHESTRA_ROOT}/revng/root"
mkdir -p "${DESTDIR}${ORCHESTRA_ROOT}/revng/root"

cd "$ORCHESTRA_ROOT"

for component in "$@"; do
  echo "$component"
  orc inspect component dependencies --installed --runtime "$component"
done | sort | uniq | \
grep -v '^glibc$' | \
while IFS= read -r component; do
  orc inspect component installed-files "${component}"
done | \
grep -vP '^include/(?!revng/PipelineC/(Prototypes|ForwardDeclarationsC)\.h)' | \
grep -vE \
  -e 'cmake' \
  -e 'node_modules' \
  -e 'node_cache' \
  -e 'man/' \
  -e '^lib64/pkgconfig/' \
  -e '^link-only/' \
  -e '^share/aclocal/' \
  -e '^share/bash-completion/' \
  -e '^share/doc/' \
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
  "${DESTDIR}${ORCHESTRA_ROOT}/revng/root/."

cd "$DESTDIR/$ORCHESTRA_ROOT/revng"

echo "Creating environment"
cp -a "$ORCHESTRA_DOTDIR/support/revng-distributable/environment" environment

# shellcheck disable=SC2094
{
  orchestra environment | grep -E "^export (PATH|REVNG_TRANSLATE_LDFLAGS|LLVM_SYMBOLIZER_PATH)"
  cat <<EOF
unset ORCHESTRA_DOTDIR
unset ORCHESTRA_ROOT
export REVNG_TRANSLATE_LDFLAGS="\$REVNG_TRANSLATE_LDFLAGS -L/lib -L/usr/lib -L/usr/lib/x86_64-linux-gnu"
EOF
} >> environment


echo "Copying README.md"
cp -a "$ORCHESTRA_DOTDIR/support/revng-distributable/README.md" .

echo "Copying revng"
cp -a "$ORCHESTRA_DOTDIR/support/revng-distributable/revng" revng


cd "$DESTDIR/$ORCHESTRA_ROOT/revng/root"

echo "Copying revng-distributable scripts"
cp -a \
  "$ORCHESTRA_DOTDIR/support/revng-distributable/revng-update" \
  "$ORCHESTRA_DOTDIR/support/revng-distributable/revng-system-info" \
  bin/

echo "Copying install-revng-dependencies"
cp -a "$ORCHESTRA_DOTDIR/support/revng-distributable/dockers/install-revng-dependencies" bin/

echo "revng-distributable updater info"
mkdir -p share/revng-distributable
echo 1 > share/revng-distributable/version

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
TEST_BINARY=$(echo "$ORCHESTRA_ROOT/share/revng/test/tests/runtime/calc-x86-64-static-revng-qa.compiled-stripped-"*)
cp -a "$TEST_BINARY" share/revng/calc-x86-64-static

echo "Generating checksums"
cd "$DESTDIR/$ORCHESTRA_ROOT/revng"
find root -type f -print0 | xargs -0 -P"$JOBS" -n100 sha256sum > checksums.sha256
sha256sum README.md environment revng >> checksums.sha256

echo "Final cleanup"
cd "${DESTDIR}${ORCHESTRA_ROOT}"
find . -not -type d -not -path './revng/*' -delete
find . -type d -empty -delete

if [ "$RUN_TESTS" -eq 1 ]; then
  # Orchestra adds quite a few environment variables, which we want to avoid to use when doing self-test
  # In order to launch self-test with as few environment variables as possible we:
  # * use `env -i` to start with no environment variables
  # * use `bash --login` to restore the ones provided at login (e.g. PATH)
  env -i -C "$DESTDIR/$ORCHESTRA_ROOT/revng" bash --login -c "set -e; ./revng daemon-self-test --revng-c \"$TEST_BINARY\""
fi
