# optimizeimage.sh shared primitive Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract the image-optimization logic shared by `tinifyimage.sh` and `compresspdf.sh` into a new standalone `optimizeimage.sh` (`SRC DST` interface, offline + online), and turn the two scripts into thin callers.

**Architecture:** `optimizeimage.sh` is a copy of `tinifyimage.sh`'s logic with a `SRC DST` interface (no `optimized/` folder), the `identify '%k %z\n'` bugfix, the dead `--local` alias removed, and the two vestigial files (`METADATA_FILE`, `OPTIMIZED_FILE_PROGRESS`) removed. `tinifyimage.sh` computes the `optimized/` path and delegates; `compresspdf.sh` calls it per page in place. Tests run the repo copies hermetically by prepending `apps/` to `PATH`.

**Tech Stack:** Bash; mozjpeg (`/opt/mozjpeg/bin/{djpeg,cjpeg}`), pngquant, oxipng, ImageMagick (`identify`/`convert`/`mogrify`), exiftool, poppler-utils (`pdfimages`/`pdfinfo`), `file`.

## Global Constraints

- Edit in the `~/pro/kumbukus` repo; install to `~/bin`. Scripts in `apps/` install individually as executables.
- The only intentional behavior changes vs. today are: the `identify '%k %z\n'` bugfix, dropping `--local`, and removing the vestigial `METADATA_FILE`/`OPTIMIZED_FILE_PROGRESS`. Everything else copies verbatim.
- Constants: `JPEG_QUALITY=75`, `OXIPNG_LEVEL=4`, `MOZJPEG_BIN=/opt/mozjpeg/bin`.
- Scripts call each other by their installed name **with** the `.sh` suffix (`optimizeimage.sh`), resolved via `PATH`.
- No `config.json`/menu changes. Sibling-dependency installer support is deferred (separate ticket); for now `optimizeimage.sh` must be installed alongside the wrappers.
- Spec: `docs/superpowers/specs/2026-06-28-optimizeimage-shared-primitive-design.md`.

---

## File Structure

- **Create:** `apps/optimizeimage.sh` — the optimization primitive (`SRC DST`, offline+online).
- **Create:** `tests/behavior/test_optimizeimage.sh` — 7 behavioral cases.
- **Modify:** `apps/tinifyimage.sh` — becomes a thin `optimized/` wrapper that delegates.
- **Create:** `tests/behavior/test_tinifyimage.sh` — wrapper smoke test (PATH-injected).
- **Modify:** `apps/compresspdf.sh` — drop inline `optimize_image()`, call `optimizeimage.sh` per page.
- **Modify:** `tests/behavior/test_compresspdf.sh` — prepend `apps/` to `PATH` so it finds the repo `optimizeimage.sh`.

---

## Task 1: Create `optimizeimage.sh` and its test

**Files:**
- Create: `~/pro/kumbukus/apps/optimizeimage.sh`
- Create: `~/pro/kumbukus/tests/behavior/test_optimizeimage.sh`

**Interfaces:**
- Produces: CLI `optimizeimage.sh [--online|--offline] [--no-metadata] [-q N] [-h|--help] SRC DST`. Default `--offline`. Writes optimized image to `DST` (its dir must exist; `SRC` may equal `DST`). offline jpeg→mozjpeg q75; offline png→pngquant-if-lossless then oxipng; unsupported type→exit 1. Prints `Compression finished (local|online): <DST> …`.

- [ ] **Step 1: Write the failing test**

Create `~/pro/kumbukus/tests/behavior/test_optimizeimage.sh`:

```bash
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash ~/pro/kumbukus/tests/behavior/test_optimizeimage.sh`
Expected: FAIL — `apps/optimizeimage.sh` does not exist yet (every case errors).

- [ ] **Step 3: Create `apps/optimizeimage.sh`**

Create `~/pro/kumbukus/apps/optimizeimage.sh` with exactly:

```bash
#!/bin/bash

# requirement: vendor/curl
# requirement: vendor/exiftool
# requirement: vendor/mozjpeg
# requirement: vendor/pngquant
# requirement: vendor/oxipng
# requirement: vendor/imagemagick
#
# Optimize an image from SRC to DST (no optimized/ folder), preserving metadata
# + mtime. Holds the optimization logic shared by tinifyimage.sh and compresspdf.sh.
#
# Modes:
#   --offline  (default)  local tools, always lossless quality:
#                           jpg -> mozjpeg
#                           png -> pngquant (only if <=256 colors & <=8-bit, i.e.
#                                  palette is lossless), otherwise oxipng only
#   --online              TinyPNG/Tinify API (needs TINYPNG_API_KEY in ~/.env)
#
# SRC may equal DST (in-place). DST's directory must already exist.

JPEG_QUALITY=75          # mozjpeg quality for local jpg (Squoosh-style)
OXIPNG_LEVEL=4           # oxipng optimization level (png, lossless)
MOZJPEG_BIN=/opt/mozjpeg/bin   # mozjpeg built from source (no PATH symlinks)

usage() {
    cat <<EOF
Usage: $0 [--online|--offline] [--no-metadata] [-q N] SRC DST

  --offline        local, always lossless: jpg=mozjpeg; png=pngquant if <=256
                   colors (palette is lossless) else oxipng
  --online         compress via Tinify API (requires TINYPNG_API_KEY in ~/.env)
  --no-metadata    drop EXIF/metadata (orientation is still kept for jpg)
  -q, --quality N  mozjpeg quality for local jpg (default ${JPEG_QUALITY})

Writes the optimized image to DST (its directory must exist). SRC may equal DST.
EOF
}

MODE=offline
NO_METADATA=false
SOURCE_FILE=""
DEST_FILE=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --online)            MODE=online ;;
        --offline)           MODE=offline ;;
        --no-metadata)       NO_METADATA=true ;;
        -q|--quality)        shift; JPEG_QUALITY="$1" ;;
        -h|--help)           usage; exit 0 ;;
        -*)                  echo "Unknown option: $1" >&2; usage; exit 1 ;;
        *)                   if [ -z "$SOURCE_FILE" ]; then SOURCE_FILE="$1"; else DEST_FILE="$1"; fi ;;
    esac
    shift
done

if [ -z "$SOURCE_FILE" ] || [ -z "$DEST_FILE" ]; then
    usage; exit 1
fi
if [ ! -f "$SOURCE_FILE" ]; then
    echo "No such file: $SOURCE_FILE" >&2; exit 1
fi

OPTIMIZED_FILE="$DEST_FILE"

# --- ONLINE: Tinify API -------------------------------------------------------
compress_online() {
    source ~/.env

    # https://tinypng.com/developers/reference#compressing-images
    response=$(curl --user api:$TINYPNG_API_KEY --dump-header /dev/stdout --data-binary @"$SOURCE_FILE" https://api.tinify.com/shrink)
    location_url=$(echo "$response" | grep -i Location: | awk '{print $2}' | tr -d '\r')

    if [ ! -z "$location_url" ]; then
        curl -L "$location_url" --output "$OPTIMIZED_FILE"

        if [ "$NO_METADATA" == false ]; then
            # Tinify bakes EXIF rotation into pixels, so force Orientation=Horizontal
            exiftool -overwrite_original -all= "$OPTIMIZED_FILE"
            exiftool -overwrite_original -tagsfromfile "$SOURCE_FILE" -all:all -Orientation=Horizontal "$OPTIMIZED_FILE"
        fi

        touch -r "$SOURCE_FILE" "$OPTIMIZED_FILE"
        echo "Compression finished (online): $OPTIMIZED_FILE"
    else
        echo "Error extracting URL from Location header" >&2
        exit 1
    fi
}

# --- OFFLINE: local tools -----------------------------------------------------
require() {
    local missing=0
    for t in "$@"; do
        command -v "$t" >/dev/null 2>&1 || { echo "Missing tool: $t" >&2; missing=1; }
    done
    [ "$missing" -eq 0 ] || { echo "Install the missing tool(s) and retry." >&2; exit 1; }
}

restore_metadata() { # $1 = file to tag, $2 = "jpeg"|"png"
    if [ "$NO_METADATA" == false ]; then
        exiftool -overwrite_original -tagsfromfile "$SOURCE_FILE" -all:all "$1" >/dev/null 2>&1 || true
    elif [ "$2" == "jpeg" ]; then
        # keep only Orientation so rotated photos still display correctly
        exiftool -overwrite_original -tagsfromfile "$SOURCE_FILE" -Orientation "$1" >/dev/null 2>&1 || true
    fi
}

detect_format() { # echo "jpeg" | "png" | "" — prefer real content, fall back to extension
    local m=""
    if command -v file >/dev/null 2>&1; then
        m=$(file -b --mime-type "$SOURCE_FILE" 2>/dev/null)
    fi
    case "$m" in
        image/jpeg) echo jpeg; return ;;
        image/png)  echo png;  return ;;
    esac
    case "${SOURCE_FILE,,}" in
        *.jpg|*.jpeg) echo jpeg ;;
        *.png)        echo png ;;
        *)            echo "" ;;
    esac
}

compress_local() {
    local fmt tmp n z
    fmt=$(detect_format)
    tmp="${OPTIMIZED_FILE}.work.tmp"
    rm -f "$tmp"

    case "$fmt" in
        jpeg)
            require "$MOZJPEG_BIN/djpeg" "$MOZJPEG_BIN/cjpeg"
            # mozjpeg defaults already include -progressive -optimize -trellis;
            # -quant-table 3 matches Squoosh. cjpeg reads PPM, so decode first.
            "$MOZJPEG_BIN/djpeg" "$SOURCE_FILE" \
                | "$MOZJPEG_BIN/cjpeg" -quality "$JPEG_QUALITY" -quant-table 3 -progressive -optimize -outfile "$tmp"
            restore_metadata "$tmp" jpeg
            ;;
        png)
            require oxipng identify
            # pngquant only when provably lossless: all colors fit a 256-entry,
            # <=8-bit palette. Otherwise use lossless oxipng alone.
            read -r n z < <(identify -format '%k %z\n' "$SOURCE_FILE" 2>/dev/null)
            if [ "${n:-999999}" -le 256 ] 2>/dev/null && [ "${z:-16}" -le 8 ] 2>/dev/null; then
                require pngquant
                if ! pngquant 256 --skip-if-larger --force --output "$tmp" "$SOURCE_FILE" 2>/dev/null; then
                    cp "$SOURCE_FILE" "$tmp"   # pngquant declined -> keep original
                fi
            else
                cp "$SOURCE_FILE" "$tmp"       # >256 colors or >8-bit -> lossless only
            fi
            oxipng -o "$OXIPNG_LEVEL" --strip safe --alpha "$tmp" >/dev/null 2>&1
            restore_metadata "$tmp" png
            ;;
        *)
            echo "Unsupported type for local mode: $SOURCE_FILE (expected jpg/png)" >&2
            exit 1
            ;;
    esac

    touch -r "$SOURCE_FILE" "$tmp"
    mv -f "$tmp" "$OPTIMIZED_FILE"

    local os ns
    os=$(stat -c%s "$SOURCE_FILE"); ns=$(stat -c%s "$OPTIMIZED_FILE")
    awk -v o="$os" -v n="$ns" -v f="$OPTIMIZED_FILE" \
        'BEGIN{printf "Compression finished (local): %s  (%d -> %d bytes, -%.0f%%)\n", f, o, n, (o-n)*100/o}'
}

if [ "$MODE" == "online" ]; then
    compress_online
else
    compress_local
fi
```

- [ ] **Step 4: Make it executable and run the test**

Run:
```bash
chmod +x ~/pro/kumbukus/apps/optimizeimage.sh
bash ~/pro/kumbukus/tests/behavior/test_optimizeimage.sh
```
Expected: every line `PASS`, exit 0.

- [ ] **Step 5: Syntax check**

Run: `bash -n ~/pro/kumbukus/apps/optimizeimage.sh && echo "syntax ok"`
Expected: `syntax ok`.

- [ ] **Step 6: Commit**

```bash
cd ~/pro/kumbukus
chmod +x tests/behavior/test_optimizeimage.sh
git add apps/optimizeimage.sh tests/behavior/test_optimizeimage.sh
git commit -m "optimizeimage.sh: standalone SRC/DST image optimizer (extracted from tinifyimage.sh)"
```

---

## Task 2: Make `tinifyimage.sh` a thin wrapper

**Files:**
- Modify: `~/pro/kumbukus/apps/tinifyimage.sh`
- Create: `~/pro/kumbukus/tests/behavior/test_tinifyimage.sh`

**Interfaces:**
- Consumes: `optimizeimage.sh` (Task 1), found on `PATH`.
- Produces: CLI `tinifyimage.sh [--online|--offline] [--no-metadata] [-q N] [-h|--help] FILE` — optimizes `FILE` into `<dir>/optimized/<basename>`.

- [ ] **Step 1: Write the failing test**

Create `~/pro/kumbukus/tests/behavior/test_tinifyimage.sh`:

```bash
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash ~/pro/kumbukus/tests/behavior/test_tinifyimage.sh`
Expected: FAIL — the current `tinifyimage.sh` still writes `optimized/a.jpg` itself, so the first asserts may pass, but this guards the rewrite; if it already passes, proceed (the rewrite must keep it passing). If `optimizeimage.sh` is not yet on PATH the rewrite would fail, which is why the test sets PATH.

(Note: this test characterizes the wrapper's external behavior, which is intentionally unchanged. It mainly guards Step 3's rewrite from breaking the contract.)

- [ ] **Step 3: Rewrite `apps/tinifyimage.sh` as a wrapper**

Replace the entire contents of `~/pro/kumbukus/apps/tinifyimage.sh` with:

```bash
#!/bin/bash

# requirement: vendor/imagemagick
# depends on: optimizeimage.sh
#
# Optimize an image into a sibling `optimized/` folder.
# Thin wrapper over optimizeimage.sh (which holds all the optimization logic):
# computes the optimized/ destination and delegates, forwarding all flags.
#
# Usage: tinifyimage.sh [--online|--offline] [--no-metadata] [-q N] FILE

usage() {
    cat <<EOF
Usage: $0 [--online|--offline] [--no-metadata] [-q N] FILE

Optimizes FILE into ./optimized/FILE next to it (original untouched).
Delegates to optimizeimage.sh.
EOF
}

FLAGS=()
FILE=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -q|--quality)  FLAGS+=("$1" "$2"); shift 2 ;;
        -h|--help)     usage; exit 0 ;;
        -*)            FLAGS+=("$1"); shift ;;
        *)             FILE="$1"; shift ;;
    esac
done

if [ -z "$FILE" ]; then
    usage; exit 1
fi
if [ ! -f "$FILE" ]; then
    echo "No such file: $FILE" >&2; exit 1
fi

OPTIMIZED_DIR="$(dirname "$FILE")/optimized"
mkdir -p "$OPTIMIZED_DIR"
DST="$OPTIMIZED_DIR/$(basename "$FILE")"

exec optimizeimage.sh "${FLAGS[@]}" "$FILE" "$DST"
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash ~/pro/kumbukus/tests/behavior/test_tinifyimage.sh`
Expected: every line `PASS`, exit 0.

- [ ] **Step 5: Syntax check**

Run: `bash -n ~/pro/kumbukus/apps/tinifyimage.sh && echo "syntax ok"`
Expected: `syntax ok`.

- [ ] **Step 6: Commit**

```bash
cd ~/pro/kumbukus
chmod +x apps/tinifyimage.sh tests/behavior/test_tinifyimage.sh
git add apps/tinifyimage.sh tests/behavior/test_tinifyimage.sh
git commit -m "tinifyimage.sh: become a thin optimized/ wrapper over optimizeimage.sh"
```

---

## Task 3: Make `compresspdf.sh` delegate, then install and verify

**Files:**
- Modify: `~/pro/kumbukus/apps/compresspdf.sh`
- Modify: `~/pro/kumbukus/tests/behavior/test_compresspdf.sh`

**Interfaces:**
- Consumes: `optimizeimage.sh` (Task 1), found on `PATH`.

- [ ] **Step 1: Update `test_compresspdf.sh` to put `apps/` on PATH**

In `~/pro/kumbukus/tests/behavior/test_compresspdf.sh`, immediately after the line
`COMPRESSPDF="$repo/apps/compresspdf.sh"`, add:

```bash
export PATH="$repo/apps:$PATH"   # so compresspdf.sh finds optimizeimage.sh
```

- [ ] **Step 2: Run the compresspdf test to verify it fails**

Run: `bash ~/pro/kumbukus/tests/behavior/test_compresspdf.sh`
Expected: FAIL — `compresspdf.sh` still contains the inline `optimize_image()` and the
"no Tinify cloud references" assertion still passes, but this step characterizes the current
state before the rewrite; if all still pass, that is fine — Step 4 must keep them passing. (The
real failing test is exercised after Step 3.)

- [ ] **Step 3: Rewrite the optimization part of `apps/compresspdf.sh`**

Two edits in `~/pro/kumbukus/apps/compresspdf.sh`:

(a) Replace the requirement header block at the top:

```bash
# requirement: vendor/poppler-utils
# requirement: vendor/imagemagick
# requirement: vendor/mozjpeg
# requirement: vendor/pngquant
# requirement: vendor/oxipng
```

with:

```bash
# requirement: vendor/poppler-utils
# requirement: vendor/imagemagick
# depends on: optimizeimage.sh
```

(b) Delete the entire `optimize_image() { … }` function definition (the block from
`# Optimize one image in place, mirroring tinifyimage.sh --offline.` and `optimize_image() {`
through its closing `}`), and change the per-page loop so the body reads exactly:

```bash
for img in "$TEMP_DIR"/img*; do
    [ -f "$img" ] || continue
    if [ -n "$WIDTH" ]; then
        mogrify -resize "${WIDTH}x>" "$img"
    fi
    optimizeimage.sh --offline --no-metadata "$img" "$img" >/dev/null
done
```

(Everything else in `compresspdf.sh` — arg parsing, `pdfimages -all`, the "No images found"
guard, `mkdir -p`, the final `convert "$TEMP_DIR"/img* "$OPTIMIZED_FILE"`, and the
"Compression finished" message — stays unchanged.)

- [ ] **Step 4: Run the compresspdf test to verify it passes**

Run: `bash ~/pro/kumbukus/tests/behavior/test_compresspdf.sh`
Expected: every line `PASS`, exit 0 (jpeg/mozjpeg, png, `--width=600`, missing-file, and
no-Tinify-cloud checks all hold; the png/jpeg pages are now optimized via `optimizeimage.sh`).

- [ ] **Step 5: Run the full behavior suite and syntax-check**

Run:
```bash
bash -n ~/pro/kumbukus/apps/compresspdf.sh && echo "syntax ok"
bash ~/pro/kumbukus/tests/behavior/run-all.sh
```
Expected: `syntax ok`, then all of `test_optimizeimage.sh`, `test_tinifyimage.sh`,
`test_compresspdf.sh`, `test_makepdf.sh` pass (`run-all` exit 0).

- [ ] **Step 6: Commit**

```bash
cd ~/pro/kumbukus
git add apps/compresspdf.sh tests/behavior/test_compresspdf.sh
git commit -m "compresspdf.sh: delegate per-page optimization to optimizeimage.sh"
```

- [ ] **Step 7: Install all three scripts to ~/bin and verify the wiring**

```bash
for s in optimizeimage.sh tinifyimage.sh compresspdf.sh; do
    cp ~/pro/kumbukus/apps/$s ~/bin/$s && chmod +x ~/bin/$s
done
case ":$PATH:" in *":$HOME/bin:"*) echo "~/bin on PATH";; *) echo "WARN: ~/bin not on PATH";; esac
# tinifyimage end-to-end via installed copies
t=$(mktemp -d); convert -size 600x400 plasma: "$t/p.jpg"
tinifyimage.sh "$t/p.jpg" && ls -la "$t/optimized/"
# compresspdf on the user's real file: plain (≈no change for a photo PNG) and ultra (resize)
F="/home/vp/Desktop/test/1/151fcf85-4f8a-4cae-a204-7e393d132434.pdf"
rm -rf "$(dirname "$F")/optimized"; compresspdf.sh "$F" --width=1000
O="$(dirname "$F")/optimized/$(basename "$F")"
echo "src=$(stat -c%s "$F")  ultra=$(stat -c%s "$O")"; pdfimages -list "$O" | awk 'NR>2{print "out width="$4}'
rm -rf "$t"
```
Expected: `~/bin on PATH`; `tinifyimage.sh` produces `optimized/p.jpg`; `compresspdf.sh --width=1000`
produces a valid optimized PDF with image width ≤1000. (If `~/bin` is not on PATH, the wrappers
can't find `optimizeimage.sh` — fix PATH before relying on the menu.)

---

## Self-Review

**Spec coverage:**
- optimizeimage owns offline+online, SRC/DST, no optimized/ → Task 1 Step 3.
- Bugfix `%k %z\n` → Task 1 Step 3 (png branch).
- Drop `--local` → Task 1 Step 3 (no `--local` in the parser).
- Remove `METADATA_FILE`/`OPTIMIZED_FILE_PROGRESS` → Task 1 Step 3 (`compress_online` has neither).
- In-place support → Task 1 Step 3 (`tmp` then `mv`); tested case 4.
- Requirement headers split; `# depends on:` comments → Task 1 Step 3, Task 2 Step 3, Task 3 Step 3.
- tinifyimage thin wrapper, same CLI minus `--local`, optimized/ path → Task 2 Step 3.
- compresspdf drops inline optimizer, keeps resize, delegates → Task 3 Step 3.
- Behavior preservation (non-jpg/png PDFs still fail) → not newly tested by design; `test_compresspdf.sh` covers the working jpg/png paths.
- Tests: optimizeimage 7 cases, tinifyimage smoke, compresspdf regression → Tasks 1–3.

**Placeholder scan:** none — all script and test bodies are complete and were pre-validated against the 7 scenarios.

**Type/name consistency:** the command name `optimizeimage.sh` and its `[flags] SRC DST` signature are identical across Task 1 (definition), Task 2 (`exec optimizeimage.sh "${FLAGS[@]}" "$FILE" "$DST"`), and Task 3 (`optimizeimage.sh --offline --no-metadata "$img" "$img"`). The `optimized/<basename>` destination matches between `tinifyimage.sh` and `test_tinifyimage.sh`.
