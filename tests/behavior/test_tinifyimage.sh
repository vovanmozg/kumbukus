#!/bin/bash
# Smoke test for apps/tinifyimage.sh (thin wrapper over optimizeimage.sh).
# Runs the repo copies hermetically by putting apps/ on PATH.
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
# shellcheck source=/dev/null
source "$repo/tests/selftest/assert.sh"

export PATH="$repo/apps:$PATH"   # so tinifyimage.sh finds optimizeimage.sh
TI="$repo/apps/tinifyimage.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

convert -size 600x400 plasma: "$work/a.jpg"
bash "$TI" "$work/a.jpg" >/dev/null
out="$work/optimized/a.jpg"
assert_eq "1" "$([ -f "$out" ] && echo 1 || echo 0)" "wrapper writes optimized/<name>"
assert_eq "image/jpeg" "$(file -b --mime-type "$out")" "output is a valid jpeg"
assert_eq "1" "$([ "$(stat -c%s "$out")" -lt "$(stat -c%s "$work/a.jpg")" ] && echo 1 || echo 0)" "output smaller than source"

# missing file -> exit 1
bash "$TI" "$work/nope.jpg" >/dev/null 2>&1
assert_eq "1" "$?" "missing file exits 1"

exit "$FAILS"
