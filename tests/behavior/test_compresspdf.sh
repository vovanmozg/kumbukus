#!/bin/bash
# Behavioral tests for apps/compresspdf.sh (local-tools PDF compression, no cloud).
# Requires: imagemagick (convert/identify), poppler-utils (pdfimages/pdfinfo),
#           mozjpeg, pngquant, oxipng.
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
# shellcheck source=/dev/null
source "$repo/tests/selftest/assert.sh"

COMPRESSPDF="$repo/apps/compresspdf.sh"
export PATH="$repo/apps:$PATH"   # so compresspdf.sh finds optimizeimage.sh
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

pages()    { pdfinfo "$1" 2>/dev/null | awk '/^Pages:/ {print $2}'; }
imgwidth() { pdfimages -list "$1" 2>/dev/null | awk 'NR>2 {print $4; exit}'; }

# Fixture A: one 1200x300 PNG page (photographic -> png lossless path).
convert -size 1200x300 plasma: "$work/page.png"
convert "$work/page.png" "$work/fixture.pdf"

# --- plain compress: valid PDF, same page count, no API key needed ---
( unset TINYPNG_API_KEY; bash "$COMPRESSPDF" "$work/fixture.pdf" >/dev/null )
assert_eq "1" "$([ -f "$work/optimized/fixture.pdf" ] && echo 1 || echo 0)" "plain compress creates optimized/fixture.pdf"
assert_eq "1" "$(pages "$work/optimized/fixture.pdf")" "plain compress keeps 1 page"

# Fixture B: jpeg page -> exercises the mozjpeg branch.
convert -size 800x400 plasma: "$work/jp.jpg"
convert "$work/jp.jpg" "$work/jpeg.pdf"
bash "$COMPRESSPDF" "$work/jpeg.pdf" >/dev/null
assert_eq "1" "$([ -f "$work/optimized/jpeg.pdf" ] && echo 1 || echo 0)" "jpeg-page compress creates output"
assert_eq "1" "$(pages "$work/optimized/jpeg.pdf")" "jpeg-page compress keeps 1 page"

# Fixture C: --width=600 downscales the embedded image to <=600 wide.
mkdir -p "$work/u"
convert "$work/page.png" "$work/u/fixture.pdf"
bash "$COMPRESSPDF" "$work/u/fixture.pdf" --width=600 >/dev/null
w=$(imgwidth "$work/u/optimized/fixture.pdf")
assert_eq "1" "$([ "${w:-9999}" -le 600 ] && echo 1 || echo 0)" "--width=600 downscales image to <=600 (got ${w})"

# --- missing file -> exit 1 ---
bash "$COMPRESSPDF" "$work/nope.pdf" >/dev/null 2>&1
assert_eq "1" "$?" "missing file exits 1"

# --- rewritten script no longer calls the Tinify cloud (the comment may still
#     mention tinifyimage.sh; we only forbid the cloud markers) ---
assert_eq "0" "$(grep -ic 'api\.tinify\.com\|TINYPNG_API_KEY' "$COMPRESSPDF")" "no Tinify cloud references remain"

exit "$FAILS"
