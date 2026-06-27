# compresspdf.sh local-tools migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the cloud-Tinify image step in `compresspdf.sh` with the same local-tools optimization that `tinifyimage.sh --offline` uses, so PDF compression works with no API key and no network.

**Architecture:** `compresspdf.sh` extracts page images with `pdfimages`, optimizes each one in place by mirroring `tinifyimage.sh` per-format logic (jpeg→mozjpeg q75; png→pngquant-if-lossless then oxipng), optionally downscaling first when `--width=N` is given, then reassembles a PDF into the sibling `optimized/` folder. Single self-contained script; no config/menu changes.

**Tech Stack:** Bash, poppler-utils (`pdfimages`/`pdfinfo`), ImageMagick (`convert`/`identify`/`mogrify`), mozjpeg (`/opt/mozjpeg/bin/{djpeg,cjpeg}`), `pngquant`, `oxipng`, `file`.

## Global Constraints

- Edit in the **`~/pro/kumbukus`** repo, then install to `~/bin`. Keep `# requirement: vendor/<dep>` headers.
- Mirror `tinifyimage.sh` offline logic literally: jpeg→mozjpeg; png→pngquant only if (`%k`≤256 colours and `%z`≤8 bit-depth) else skip pngquant, then oxipng. Non-jpg/png images pass through unchanged.
- Constants match `tinifyimage.sh`: `JPEG_QUALITY=75`, `OXIPNG_LEVEL=4`, `MOZJPEG_BIN=/opt/mozjpeg/bin`.
- `--width=N` resizes each page image first with `mogrify -resize "${N}x>"` (shrink-only; the `>` prevents upscaling narrower pages).
- Remove entirely: `source ~/.env`, `TINYPNG_API_KEY` + the `curl … api.tinify.com` block, the `--compress`/`jpegoptim` path, the `LOG_FILE`/`FILE_HASH` bookkeeping, the `.tmp` touch/remove dance. Use `mkdir -p` for `optimized/`. No `exiftool` step.
- Output path unchanged: `<dir>/optimized/<name>.pdf`. CLI: `compresspdf.sh <file.pdf> [--width=<px>]`.
- Spec: `docs/superpowers/specs/2026-06-27-compresspdf-local-tools-design.md`.

---

## File Structure

- **Modify:** `~/pro/kumbukus/apps/compresspdf.sh` — full rewrite to local-tools optimization.
- **Create:** `~/pro/kumbukus/tests/behavior/test_compresspdf.sh` — behavioral test (png lossless path, jpeg/mozjpeg path, `--width` resize, no-Tinify assertion).

---

## Task 1: Rewrite `compresspdf.sh` to use local tools

**Files:**
- Modify: `~/pro/kumbukus/apps/compresspdf.sh`
- Create: `~/pro/kumbukus/tests/behavior/test_compresspdf.sh`

**Interfaces:**
- Consumes: nothing (standalone CLI).
- Produces: CLI `compresspdf.sh <file.pdf> [--width=<px>]`. Writes `<dir>/optimized/<name>.pdf`, original untouched. No `~/.env`/network dependency. Exit 1 on missing file / unknown option; exit 0 (with message) when the PDF yields no images.

- [ ] **Step 1: Write the failing test**

Create `~/pro/kumbukus/tests/behavior/test_compresspdf.sh`:

```bash
#!/bin/bash
# Behavioral tests for apps/compresspdf.sh (local-tools PDF compression, no cloud).
# Requires: imagemagick (convert/identify), poppler-utils (pdfimages/pdfinfo),
#           mozjpeg, pngquant, oxipng.
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
# shellcheck source=/dev/null
source "$repo/tests/selftest/assert.sh"

COMPRESSPDF="$repo/apps/compresspdf.sh"
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

# --- rewritten script no longer references Tinify ---
assert_eq "0" "$(grep -ic 'tinify\|TINYPNG' "$COMPRESSPDF")" "no Tinify references remain"

exit "$FAILS"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash ~/pro/kumbukus/tests/behavior/test_compresspdf.sh`
Expected: FAIL — the current script references Tinify (last assertion fails) and, without `TINYPNG_API_KEY`, may error/exit non-zero on the compress runs, so several assertions fail.

- [ ] **Step 3: Rewrite `compresspdf.sh`**

Replace the entire contents of `~/pro/kumbukus/apps/compresspdf.sh` with:

```bash
#!/bin/bash

# requirement: vendor/poppler-utils
# requirement: vendor/imagemagick
# requirement: vendor/mozjpeg
# requirement: vendor/pngquant
# requirement: vendor/oxipng
#
# Compress a PDF by re-optimizing its page images with local tools (no cloud).
#   compresspdf.sh <file.pdf> [--width=<px>]
# Output goes to <dir>/optimized/<name>.pdf; the original is untouched.
# Page images are optimized like tinifyimage.sh --offline:
#   jpeg -> mozjpeg (q75); png -> pngquant if losslessly quantizable, then oxipng.
# With --width=N each page image is first downscaled to N px wide (shrink only).

set -euo pipefail

JPEG_QUALITY=75
OXIPNG_LEVEL=4
MOZJPEG_BIN=/opt/mozjpeg/bin

if [ "$#" -lt 1 ]; then
    echo "Using: $0 <file.pdf> [--width=<px>]"
    exit 1
fi

SOURCE_PDF=""
WIDTH=""
for arg in "$@"; do
    case "$arg" in
        --width=*) WIDTH="${arg#*=}" ;;
        -*)        echo "Unknown option: $arg" >&2; exit 1 ;;
        *)         SOURCE_PDF="$arg" ;;
    esac
done

if [ -z "$SOURCE_PDF" ] || [ ! -f "$SOURCE_PDF" ]; then
    echo "No such file: $SOURCE_PDF" >&2
    exit 1
fi

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Extract page images.
pdfimages -all "$SOURCE_PDF" "$TEMP_DIR/img"
if ! ls "$TEMP_DIR"/img* >/dev/null 2>&1; then
    echo "No images found in $SOURCE_PDF"
    exit 0
fi

# Optimize one image in place, mirroring tinifyimage.sh --offline.
optimize_image() {
    local img="$1" fmt m n z
    m=$(file -b --mime-type "$img" 2>/dev/null || true)
    case "$m" in
        image/jpeg) fmt=jpeg ;;
        image/png)  fmt=png ;;
        *)
            case "${img,,}" in
                *.jpg|*.jpeg) fmt=jpeg ;;
                *.png)        fmt=png ;;
                *)            fmt="" ;;
            esac
            ;;
    esac

    case "$fmt" in
        jpeg)
            "$MOZJPEG_BIN/djpeg" "$img" \
                | "$MOZJPEG_BIN/cjpeg" -quality "$JPEG_QUALITY" -quant-table 3 -progressive -optimize -outfile "$img.tmp"
            mv -f "$img.tmp" "$img"
            ;;
        png)
            read -r n z < <(identify -format '%k %z' "$img" 2>/dev/null || echo "999999 16")
            if [ "${n:-999999}" -le 256 ] 2>/dev/null && [ "${z:-16}" -le 8 ] 2>/dev/null; then
                if pngquant 256 --skip-if-larger --force --output "$img.q" "$img" 2>/dev/null; then
                    mv -f "$img.q" "$img"
                fi
            fi
            oxipng -o "$OXIPNG_LEVEL" --strip safe --alpha "$img" >/dev/null 2>&1 || true
            ;;
        *)
            : # leave non jpg/png images unchanged
            ;;
    esac
}

for img in "$TEMP_DIR"/img*; do
    [ -f "$img" ] || continue
    if [ -n "$WIDTH" ]; then
        mogrify -resize "${WIDTH}x>" "$img"
    fi
    optimize_image "$img"
done

OPTIMIZED_DIR=$(dirname "$SOURCE_PDF")/optimized
mkdir -p "$OPTIMIZED_DIR"
OPTIMIZED_FILE="$OPTIMIZED_DIR/$(basename "$SOURCE_PDF")"

convert "$TEMP_DIR"/img* "$OPTIMIZED_FILE"
echo "Compression finished: $OPTIMIZED_FILE"
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash ~/pro/kumbukus/tests/behavior/test_compresspdf.sh`
Expected: every line `PASS`, exit code 0.

- [ ] **Step 5: Sanity-check shell syntax**

Run: `bash -n ~/pro/kumbukus/apps/compresspdf.sh && echo "syntax ok"`
Expected: `syntax ok`.

- [ ] **Step 6: Commit**

```bash
cd ~/pro/kumbukus
chmod +x apps/compresspdf.sh tests/behavior/test_compresspdf.sh
git add apps/compresspdf.sh tests/behavior/test_compresspdf.sh
git commit -m "compresspdf.sh: compress page images with local tools (mozjpeg/pngquant/oxipng), drop Tinify"
```

---

## Task 2: Install to ~/bin and verify on the real file

**Files:** none (install + manual verification only).

**Interfaces:**
- Consumes: the rewritten `apps/compresspdf.sh` from Task 1.

- [ ] **Step 1: Install the script to ~/bin**

```bash
cp ~/pro/kumbukus/apps/compresspdf.sh ~/bin/compresspdf.sh
chmod +x ~/bin/compresspdf.sh
diff ~/bin/compresspdf.sh ~/pro/kumbukus/apps/compresspdf.sh && echo "INSTALLED OK"
```
Expected: `INSTALLED OK`.

- [ ] **Step 2: Verify on the user's real test PDF (plain compress)**

```bash
F="/home/vp/Desktop/test/1/151fcf85-4f8a-4cae-a204-7e393d132434.pdf"
rm -rf "$(dirname "$F")/optimized"
~/bin/compresspdf.sh "$F"
ls -la "$(dirname "$F")/optimized/" && pdfinfo "$(dirname "$F")/optimized/$(basename "$F")" | awk '/^Pages:/'
```
Expected: an `optimized/…pdf` is produced and is a valid 1-page PDF. (Size may be close to the original — that page is a full-colour photo extracted as PNG, so the lossless path is expected to give little reduction; this is the agreed behavior.)

- [ ] **Step 3: Verify ultra compress actually shrinks**

```bash
F="/home/vp/Desktop/test/1/151fcf85-4f8a-4cae-a204-7e393d132434.pdf"
rm -rf "$(dirname "$F")/optimized"
~/bin/compresspdf.sh "$F" --width=1000
O="$(dirname "$F")/optimized/$(basename "$F")"
echo "src=$(stat -c%s "$F")  ultra=$(stat -c%s "$O")"
pdfimages -list "$O" | awk 'NR>2 {print "out width="$4}'
```
Expected: `ultra` byte size is clearly smaller than `src`, and the embedded image width is ≤1000.

---

## Self-Review

**Spec coverage:**
- Mirror tinifyimage offline per-format → Task 1 Step 3 (`optimize_image`).
- Replicate inline (not shell out) → Task 1 Step 3 (logic is inline).
- Remove `--compress`/jpegoptim, Tinify, `~/.env`, LOG_FILE/FILE_HASH, `.tmp` dance; `mkdir -p`; no exiftool → Task 1 Step 3 (none present) + Global Constraints; asserted by the "no Tinify references" test.
- `--width=N` shrink-only resize → Task 1 Step 3 (`mogrify -resize "${WIDTH}x>"`); covered by Fixture C test and Task 2 Step 3.
- Constants match tinifyimage → Task 1 Step 3.
- Requirement headers updated → Task 1 Step 3.
- Output path `<dir>/optimized/<name>.pdf` unchanged → Task 1 Step 3.
- Works with no key/network → Fixture A test (`unset TINYPNG_API_KEY`) + Task 2.
- Testing approach (valid PDF, page count, resize width, no-Tinify) → Task 1 Step 1.

**Placeholder scan:** none — full script and test bodies are present.

**Type/name consistency:** the CLI `compresspdf.sh <file.pdf> [--width=<px>]` and output path `<dir>/optimized/<name>.pdf` are identical across Task 1, Task 2, and the test. Helper `optimize_image` is the only internal function and is defined before use.
