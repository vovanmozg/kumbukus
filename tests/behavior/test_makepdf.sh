#!/bin/bash
# Behavioral tests for apps/makepdf.sh (file-or-directory → PDF, non-overwriting).
# Requires: imagemagick (convert), pdfinfo (poppler-utils).
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
# shellcheck source=/dev/null
source "$repo/tests/selftest/assert.sh"

MAKEPDF="$repo/apps/makepdf.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkimg() { convert -size 10x10 "xc:$2" "$1"; }   # mkimg <path> <color>
pages() { pdfinfo "$1" 2>/dev/null | awk '/^Pages:/ {print $2}'; }

# --- single image file ---
mkdir -p "$work/single"
mkimg "$work/single/photo.jpg" white
bash "$MAKEPDF" "$work/single/photo.jpg" >/dev/null
assert_eq "1" "$([ -f "$work/single/photo.pdf" ] && echo 1 || echo 0)" "file mode creates photo.pdf"
assert_eq "1" "$(pages "$work/single/photo.pdf")" "file mode PDF has 1 page"

# --- single image, second run does not overwrite ---
bash "$MAKEPDF" "$work/single/photo.jpg" >/dev/null
assert_eq "1" "$([ -f "$work/single/photo-1.pdf" ] && echo 1 || echo 0)" "file mode second run writes photo-1.pdf"

# --- directory of 2 images → one 2-page PDF next to the folder ---
mkdir -p "$work/album"
mkimg "$work/album/01.jpg" white
mkimg "$work/album/02.png" black
bash "$MAKEPDF" "$work/album" >/dev/null
assert_eq "1" "$([ -f "$work/album.pdf" ] && echo 1 || echo 0)" "dir mode creates album.pdf next to folder"
assert_eq "2" "$(pages "$work/album.pdf")" "dir mode PDF has 2 pages"

# --- directory, second run does not overwrite ---
bash "$MAKEPDF" "$work/album" >/dev/null
assert_eq "1" "$([ -f "$work/album-1.pdf" ] && echo 1 || echo 0)" "dir mode second run writes album-1.pdf"

# --- empty directory → exit 0, no PDF ---
mkdir -p "$work/empty"
bash "$MAKEPDF" "$work/empty" >/dev/null
rc=$?
assert_eq "0" "$rc" "empty dir exits 0"
assert_eq "0" "$([ -f "$work/empty.pdf" ] && echo 1 || echo 0)" "empty dir produces no PDF"

# --- bogus argument → non-zero exit ---
bash "$MAKEPDF" "$work/does-not-exist" >/dev/null 2>&1
assert_eq "1" "$?" "missing path exits 1"

exit "$FAILS"
