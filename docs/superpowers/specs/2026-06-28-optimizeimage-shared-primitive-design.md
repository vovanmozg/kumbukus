# Extract image optimization into a shared `optimizeimage.sh` primitive

## Problem

The local image-optimization logic (mozjpeg for jpeg; pngquant-if-lossless + oxipng for png)
now lives in **two** scripts — `tinifyimage.sh` (`compress_local` + `detect_format`) and
`compresspdf.sh` (`optimize_image`). The copies have already diverged in one session:
`compresspdf.sh` fixed an `identify -format '%k %z'` EOF/`read` bug that `tinifyimage.sh` still
carries, plus differences in in-place vs temp-copy handling, `require()` checks, and `|| true`
guards. This is classic DRY drift, with a latent bug in one copy.

## Goal

Introduce a third script, `optimizeimage.sh`, that owns the full image-optimization logic
(offline local tools **and** the online Tinify mode), exposed through a plain `SRC DST`
interface with no `optimized/` folder knowledge. `tinifyimage.sh` and `compresspdf.sh` become
thin callers. The duplicated optimization code disappears.

## Decisions (from brainstorming)

- **optimizeimage owns both modes** — offline (mozjpeg/pngquant/oxipng) and online (Tinify
  `--online`). `tinifyimage.sh` keeps no optimization logic of its own.
- **Resize stays in `compresspdf.sh`** — optimizeimage is a pure "optimize this image"
  primitive and knows nothing about `--width`. compresspdf does `mogrify -resize` itself, then
  calls optimizeimage.
- **Only direct vendor deps declared.** optimizeimage carries the
  mozjpeg/pngquant/oxipng/imagemagick/curl/exiftool requirements; compresspdf keeps its direct
  ones (poppler-utils, imagemagick); tinifyimage has no direct vendor tool of its own. The
  dependency on the sibling `optimizeimage` is recorded as a **plain comment**, not a
  `# requirement:` line.
- **Defer installer tooling.** `installapps`/`requirements.sh` only understand
  `# requirement: vendor/<dep>`; teaching them to install sibling scripts is a separate later
  ticket. For now, installing the wrappers also requires installing `optimizeimage.sh`
  manually — a documented limitation.

## Source of truth

`~/pro/kumbukus` repo. New script `apps/optimizeimage.sh` → installs to `~/bin`. Modified:
`apps/tinifyimage.sh`, `apps/compresspdf.sh`. No `config.json`/menu changes (menu still calls
`tinifyimage.sh %f`, `tinifyimage.sh %f --no-metadata`, `compresspdf.sh %f`,
`compresspdf.sh %f --width=1000`).

## Design

### Component map

```
                    optimizeimage.sh        (offline local + online Tinify; SRC DST)
                   /                \
   tinifyimage.sh (optimized/ wrapper)   compresspdf.sh (pdfimages → resize → optimize → reassemble)
```

### 1. `apps/optimizeimage.sh` (new)

Built by copying `tinifyimage.sh`'s logic, fixing bugs, and changing the interface.

**Interface:** `optimizeimage.sh [--online|--offline|--local] [--no-metadata] [-q N] [-h|--help] SRC DST`
- Default mode `--offline`. `--local` is an accepted alias of `--offline` (preserved from
  today's `tinifyimage.sh`). `-h`/`--help` prints usage and exits 0.
- **Unsupported type** (offline, input neither jpeg nor png): prints a message and exits 1 —
  today's `tinifyimage.sh` behavior, kept as-is. See "Behavior preservation" below for why this
  is faithful for `compresspdf.sh` too.
- Writes the optimized image to **DST** (not `optimized/<basename>`). The directory of DST
  must already exist — optimizeimage does not create directories.
- **In-place supported:** `SRC` may equal `DST`. Implementation writes to a temp file
  (`${DST}.work.tmp`) then `mv -f` over DST, so SRC is fully read before being replaced. (This
  is the supported in-place path for **offline** mode; online in-place is out of scope.)
- **Metadata** (offline and online): unless `--no-metadata`, restore tags from SRC onto DST
  via `exiftool`; preserve mtime with `touch -r SRC DST`. Same behavior as today's
  `tinifyimage.sh`, just SRC→DST instead of SRC→optimized.
- **Format detection:** `file -b --mime-type` → jpeg/png, fall back to extension.
- **offline jpeg:** `djpeg SRC | cjpeg -quality $JPEG_QUALITY -quant-table 3 -progressive -optimize`.
- **offline png:** if `%k`≤256 colours and `%z`≤8 bit-depth → `pngquant 256 --skip-if-larger
  --force` (keep original if it declines), else lossless only; then `oxipng -o4 --strip safe
  --alpha`.
- **online:** Tinify API (`source ~/.env`, `TINYPNG_API_KEY`, `curl … api.tinify.com`),
  writing to DST.
- **Constants:** `JPEG_QUALITY=75`, `OXIPNG_LEVEL=4`, `MOZJPEG_BIN=/opt/mozjpeg/bin`.
- **`require()`** tool checks retained.
- **Report:** prints the same messages today's `tinifyimage.sh` prints — offline
  `Compression finished (local): <DST>  (o -> n bytes, -X%)`, online
  `Compression finished (online): <DST>` — so wrapper stdout is unchanged. Callers may redirect.

**Metadata semantics — copy verbatim from today's `tinifyimage.sh`, do not paraphrase:**
- `--no-metadata` false: restore all tags from SRC onto DST (`exiftool -tagsfromfile SRC
  -all:all DST`).
- `--no-metadata` true: jpeg keeps **only** `Orientation`; png keeps **nothing**.
- online mode: after download, strip all then restore from SRC and force
  `Orientation=Horizontal` (Tinify bakes rotation into pixels) — exactly as the current
  `compress_online` does.

**Bugs fixed during the copy:**
- `identify -format '%k %z\n'` (add the newline so `read` doesn't fail at EOF — the bug
  `tinifyimage.sh` currently carries). This is the only intentional behavior change; everything
  else is preserved byte-for-byte in effect.

**Requirement headers:**
```
# requirement: vendor/curl
# requirement: vendor/exiftool
# requirement: vendor/mozjpeg
# requirement: vendor/pngquant
# requirement: vendor/oxipng
# requirement: vendor/imagemagick
```

### 2. `apps/tinifyimage.sh` (becomes a thin wrapper)

- Keeps the **exact** CLI it has today — `[--online|--offline|--local] [--no-metadata] [-q N]
  [-h|--help] FILE`, including the `--local` alias and `-h`/usage — so the Nautilus menu entries
  (`tinifyimage.sh %f`, `tinifyimage.sh %f --no-metadata`) and any terminal use keep working
  unchanged.
- Computes `DST="$(dirname SRC)/optimized/$(basename SRC)"`, `mkdir -p` that folder, and
  delegates by forwarding all of its flags: `optimizeimage <same flags> "$SRC" "$DST"`.
- Removes all optimization/online code (now in optimizeimage), `require()`, `detect_format`,
  `compress_local`, `compress_online`.
- Direct vendor deps: none of its own; add a comment `# depends on: optimizeimage.sh` (not a
  `# requirement:` line).

### 3. `apps/compresspdf.sh` (drops the inline optimizer)

- Removes the inline `optimize_image()` function.
- In the per-page loop: keep `mogrify -resize "${WIDTH}x>"` when `--width` is given, then call
  `optimizeimage --offline --no-metadata "$img" "$img" >/dev/null` (in-place; metadata is
  meaningless for intermediate page images; stdout suppressed to avoid a line per page).
- jpg/png page failures abort under `set -euo pipefail` exactly as the current inline
  `optimize_image()` does. See "Behavior preservation" for non-jpg/png pages.
- Requirement headers keep only its direct tools:
  ```
  # requirement: vendor/poppler-utils
  # requirement: vendor/imagemagick
  ```
  plus a comment `# depends on: optimizeimage.sh`.

## Behavior preservation (verified against the current scripts)

Every current behavior is preserved; the only intentional change is the `identify` newline
bugfix.

- **tinifyimage CLI surface** — `--online`, `--offline`, `--local` alias, `--no-metadata`,
  `-q/--quality N`, `-h/--help`/usage, error+usage on unknown `-*`, exit 1 on missing/empty
  file — all forwarded to optimizeimage. Menu entries unaffected.
- **Metadata** — offline jpeg keeps Orientation under `--no-metadata` and full tags otherwise;
  offline png keeps nothing under `--no-metadata`; online bakes `Orientation=Horizontal`. Copied
  verbatim (see metadata note above).
- **Output messages** — `(local)`/`(online)` + `-X%` preserved.
- **compresspdf on jpg/png PDFs** — identical output (optimizeimage runs the same
  mozjpeg/pngquant/oxipng pipeline that compresspdf ran inline).
- **compresspdf on non-jpg/png PDFs (CCITT/JBIG2/CMYK-as-ppm, etc.)** — *empirically, the
  current script already fails* on these: `pdfimages -all` emits a non-jpg/png file (and a
  `.params` sidecar), and the final `convert "$TEMP_DIR"/img* …` has no decode delegate for
  CCITT/PARAMS, so it exits 1 with no usable output. The refactor reproduces a failing exit on
  the same inputs (optimizeimage exits 1 on the unsupported page first). No working behavior is
  lost. A `--skip-unsupported` pass-through was considered and **rejected**: it would not make
  such PDFs succeed (the downstream `convert` still can't read CCITT), so it adds surface
  without preserving or fixing anything. Genuinely supporting exotic page formats is a separate
  future improvement, explicitly out of scope here.

## Error handling

- optimizeimage validates: SRC exists and is a file; DST given; unknown option → usage + exit
  1; unsupported type in offline mode → message + exit 1 (as today).
- Wrappers: if `optimizeimage` is not installed, the call fails with the shell's
  "command not found" (exit 127). A friendlier guard is **not** added now (installer support
  is deferred); the missing-sibling limitation is documented in this spec.

## Out of scope (YAGNI / deferred)

- Teaching `installapps`/`requirements.sh` to install sibling-script dependencies — separate
  ticket.
- Adding `--width`/resize to optimizeimage.
- Online in-place (`SRC==DST` with `--online`).
- Renaming around the pre-existing, similarly-named `optimizeimagejpegoptim.sh` (kept as is).

## Testing

New `tests/behavior/test_optimizeimage.sh` (reusing `tests/selftest/assert.sh`; requires
imagemagick/mozjpeg/pngquant/oxipng/file):

1. **offline jpeg** — a generated jpeg → DST smaller than SRC and still a valid JPEG
   (`file --mime-type` = image/jpeg).
2. **offline png palette** (≤256 colours, 8-bit) → DST exists, valid PNG, not larger than SRC.
3. **offline png photo** (>256 colours) → DST exists and is a valid PNG (lossless path runs
   without error).
4. **in-place** (`SRC==DST`) → the file is optimized in place and remains valid.
5. **SRC≠DST** → DST created in an existing directory, SRC untouched.
6. **unsupported type** (e.g. a `.txt`) in offline mode → exit 1.
7. **`--no-metadata` on a jpeg** → DST is valid and its `Orientation` tag is preserved while
   other EXIF is dropped (guards the metadata nuance).

Regression:
- `tests/behavior/test_compresspdf.sh` continues to pass (now exercising optimizeimage via the
  per-page call) — including the jpeg/mozjpeg, png, `--width=600`, and no-Tinify-cloud checks.
- A minimal `test_tinifyimage.sh` smoke check: `tinifyimage.sh` (offline, default) on a
  generated jpeg produces a valid `optimized/<name>` smaller than the source — confirming the
  wrapper still works end-to-end.

Not asserted (would be testing a pre-existing failure, not a regression): non-jpg/png PDFs
continue to fail in `compresspdf` exactly as they do today; no test pretends they succeed.

Online (Tinify) paths are not tested automatically (need a key and network).
