#!/bin/bash
# Behavioral tests for apps/optimizeimage.sh (SRC DST image optimizer, offline).
# Requires: imagemagick, mozjpeg, pngquant, oxipng, exiftool, file.
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
# shellcheck source=/dev/null
source "$repo/tests/selftest/assert.sh"

OI="$repo/apps/optimizeimage.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mime() { file -b --mime-type "$1"; }
size() { stat -c%s "$1"; }

# 1. offline jpeg -> smaller, still jpeg
convert -size 600x400 plasma: "$work/a.jpg"
bash "$OI" "$work/a.jpg" "$work/a.out.jpg" >/dev/null
assert_eq "image/jpeg" "$(mime "$work/a.out.jpg")" "jpeg stays jpeg"
assert_eq "1" "$([ "$(size "$work/a.out.jpg")" -lt "$(size "$work/a.jpg")" ] && echo 1 || echo 0)" "jpeg gets smaller"

# 2. offline png palette (<=256 colours, 8-bit) -> valid png, not larger
convert -size 200x200 plasma: -colors 16 -type Palette "$work/pal.png"
bash "$OI" "$work/pal.png" "$work/pal.out.png" >/dev/null
assert_eq "image/png" "$(mime "$work/pal.out.png")" "palette stays png"
assert_eq "1" "$([ "$(size "$work/pal.out.png")" -le "$(size "$work/pal.png")" ] && echo 1 || echo 0)" "palette not larger"

# 3. offline png photo (>256 colours) -> valid png
convert -size 600x400 plasma: "$work/photo.png"
bash "$OI" "$work/photo.png" "$work/photo.out.png" >/dev/null
assert_eq "image/png" "$(mime "$work/photo.out.png")" "photo png stays png"

# 4. in-place (SRC==DST) -> still valid
cp "$work/a.jpg" "$work/inplace.jpg"
bash "$OI" "$work/inplace.jpg" "$work/inplace.jpg" >/dev/null
assert_eq "image/jpeg" "$(mime "$work/inplace.jpg")" "in-place stays valid jpeg"

# 5. SRC != DST -> src untouched, dst created
before=$(md5sum "$work/a.jpg" | awk '{print $1}')
bash "$OI" "$work/a.jpg" "$work/d5.jpg" >/dev/null
assert_eq "$before" "$(md5sum "$work/a.jpg" | awk '{print $1}')" "src untouched"
assert_eq "1" "$([ -f "$work/d5.jpg" ] && echo 1 || echo 0)" "dst created"

# 6. unsupported type -> exit 1
echo hi > "$work/x.txt"
bash "$OI" "$work/x.txt" "$work/x.out" >/dev/null 2>&1
assert_eq "1" "$?" "unsupported type exits 1"

# 7. --no-metadata on jpeg keeps Orientation, drops other EXIF
cp "$work/a.jpg" "$work/m.jpg"
exiftool -overwrite_original -Orientation#=6 -Artist=Bob "$work/m.jpg" >/dev/null 2>&1
bash "$OI" --no-metadata "$work/m.jpg" "$work/m.out.jpg" >/dev/null
assert_eq "6" "$(exiftool -s3 -Orientation -n "$work/m.out.jpg" 2>/dev/null)" "Orientation preserved"
assert_eq "" "$(exiftool -s3 -Artist "$work/m.out.jpg" 2>/dev/null)" "other EXIF dropped"

exit "$FAILS"
