# Local-tools compression in `compresspdf.sh`

## Problem

`compresspdf.sh` compresses a PDF by extracting its page images, shrinking them, and
re-assembling a PDF in a sibling `optimized/` folder. Its only shrink mechanism is an inline
call to the **Tinify cloud API** (`curl … api.tinify.com`), keyed by `TINYPNG_API_KEY` from
`~/.env`. That key is no longer present, so the Tinify call fails silently, the page images
pass through unchanged, and the "compressed" PDF comes out the same size.

Meanwhile the sibling script `tinifyimage.sh` was already reworked to use **local tools by
default** (mozjpeg / pngquant / oxipng), with Tinify demoted to an opt-in `--online` mode.
`compresspdf.sh` was never migrated. This spec migrates it to the same local approach.

## Decisions (from brainstorming)

- **Mirror `tinifyimage.sh` offline logic literally**, per-format:
  - jpeg → mozjpeg; png → pngquant (only if losslessly quantizable) + oxipng.
  - Consequence accepted by the user: a full-colour photographic page extracted as PNG stays
    lossless (oxipng only), so plain `PDF compress` barely shrinks scans/photos. Real
    reduction for those comes from `PDF ultra compress` (`--width=1000`), which resizes first.
- **Replicate the logic inline** in `compresspdf.sh` (not by shelling out to
  `tinifyimage.sh`) — self-contained, no `optimized/`-path coupling. Accepts that the
  per-image optimization code is duplicated between the two scripts.
- **Remove the `--compress` option** (jpegoptim pass). It has existed since the script's first
  commit but is invoked by no menu entry in any historical `config.json`; it is dead code and
  not part of the tinifyimage approach. Only `--width=N` remains.
- **No EXIF restore.** `tinifyimage.sh` restores metadata onto a user-facing image; here the
  images are intermediate, per-page extractions with no source metadata worth preserving, so
  the `exiftool` step is omitted.

## Source of truth

`~/pro/kumbukus` repo. Script: `apps/compresspdf.sh` → installed to `~/bin`. No config change
(the `PDF compress` / `PDF ultra compress` menu entries already call
`compresspdf.sh %f` and `compresspdf.sh %f --width=1000`).

## Tool inventory (verified present)

`pdfimages` (poppler-utils), `convert`/`identify`/`mogrify` (ImageMagick),
`/opt/mozjpeg/bin/{djpeg,cjpeg}`, `pngquant`, `oxipng`, `file`. (`exiftool` exists but is
intentionally unused here.)

## Design

### Interface

```
compresspdf.sh <file.pdf> [--width=<px>]
```

Output: `<dir>/optimized/<name>.pdf`. Original untouched.

### Flow

1. **Guard**: exactly one PDF path argument; parse optional `--width=N`.
2. **Extract**: `pdfimages -all "$SRC" "$TEMP/img"` into a fresh temp dir (`mktemp -d`).
   If no images are produced, report and exit 0 (nothing to do).
3. **Per page image** (`for img in "$TEMP"/img*`):
   - If `--width=N` given: `mogrify -resize "${N}x>" "$img"` (in place). The `>` suffix means
     "shrink only" — pages already narrower than N are left alone instead of being upscaled
     (a small, deliberate fix over the current bare `${WIDTH}x`, which would enlarge them).
   - Optimize in place, mirroring `tinifyimage.sh` offline:
     - **Detect format** via `file -b --mime-type` (fall back to extension): `jpeg` | `png` |
       other.
     - **jpeg**: `djpeg "$img" | cjpeg -quality 75 -quant-table 3 -progressive -optimize
       -outfile "$img.tmp"` then move `$img.tmp` → `$img`.
     - **png**: read `identify -format '%k %z'`; if colours ≤256 and bit-depth ≤8, run
       `pngquant 256 --skip-if-larger --force --output "$img.q" "$img"` (keep original if
       pngquant declines), else use the image as-is; then `oxipng -o4 --strip safe --alpha`
       in place.
     - **other** (ppm/tiff/jbig2/…): leave unchanged (tinifyimage only handles jpg/png too).
4. **Assemble**: `mkdir -p "$OPTIMIZED_DIR"`, then `convert "$TEMP"/img* "$OPTIMIZED_FILE"`.
5. **Cleanup**: remove the temp dir (a `trap … EXIT` is the robust form).

### Constants (match `tinifyimage.sh`)

`JPEG_QUALITY=75`, `OXIPNG_LEVEL=4`, `MOZJPEG_BIN=/opt/mozjpeg/bin`.

### Requirement headers

Replace the script header with:
```
# requirement: vendor/poppler-utils
# requirement: vendor/imagemagick
# requirement: vendor/mozjpeg
# requirement: vendor/pngquant
# requirement: vendor/oxipng
```

### Removed from the current script

`source ~/.env`; `TINYPNG_API_KEY` + the `curl … api.tinify.com` block; the `--compress` /
`COMPRESS_LEVEL` / `jpegoptim` path; the `LOG_FILE` logging (it is referenced before it is
assigned — a latent bug) and the CRC32/`FILE_HASH` bookkeeping; the `${OPTIMIZED_FILE}.tmp`
touch/remove dance. `mkdir` for `optimized/` becomes `mkdir -p`.

## Behavior summary (honest)

- **PDF compress** (no `--width`): per-format lossless/near-lossless. Photo-as-PNG pages
  barely shrink; palette PNG / screenshot pages shrink; JPEG pages re-encoded at q75.
- **PDF ultra compress** (`--width=1000`): downsize each page image to 1000px wide, then
  optimize → real reduction, including photographic scans.
- Works with no `TINYPNG_API_KEY` and no network.

## Testing

Behavioral test (same style as `tests/behavior/test_makepdf.sh`, reusing
`tests/selftest/assert.sh`), requiring `convert`/`pdfimages`/`pdfinfo`:

1. **Builds a fixture PDF** from a generated image (`convert -size WxH … page.png`, then
   `convert page.png fixture.pdf`).
2. **Plain compress** → asserts `optimized/fixture.pdf` exists, is valid (`pdfinfo` parses),
   and has the same page count (1).
3. **`--width=600`** on a fixture whose page image is 1200px wide → asserts the embedded
   image width in the output is ≤600 (`pdfimages -list` width column). This deterministically
   proves the resize path without depending on lossy-codec byte sizes.
4. **No-network / no-key** → the test runs without `TINYPNG_API_KEY` set and still succeeds,
   proving Tinify is gone (the rewritten script never references it).

(Per-page byte-size reductions are not asserted, since lossless paths legitimately may not
shrink a synthetic fixture.)

## Out of scope (YAGNI)

- Converting photographic PNG pages to JPEG for stronger compression (the hybrid/"all→JPEG"
  approaches were considered and explicitly declined in favour of the literal tinifyimage
  mirror).
- Restoring the `--compress` option.
- Any `config.json` / menu changes.
