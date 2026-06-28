# Extract image optimization into a shared `optimizeimage.sh` primitive

## Problem

The local image-optimization logic (mozjpeg for jpeg; pngquant-if-lossless + oxipng for png)
lives in **two** scripts — `tinifyimage.sh` (`compress_local` + `detect_format`) and
`compresspdf.sh` (`optimize_image`). The copies already diverged within one session:
`compresspdf.sh` fixed an `identify '%k %z'` bug (`read` fails at EOF) that `tinifyimage.sh`
still carries. Classic DRY drift, with a latent bug in one copy.

## Goal and approach

Introduce a third script, `optimizeimage.sh`, that owns all the optimization logic (offline +
online Tinify), with a plain `SRC DST` interface and no knowledge of the `optimized/` folder.
`tinifyimage.sh` and `compresspdf.sh` become thin callers; the duplicated optimization code
disappears.

**`optimizeimage.sh` is created by copying `tinifyimage.sh`, not by rewriting it.** The
authoritative source for the optimization / metadata / online logic is the file
`apps/tinifyimage.sh` itself; this spec does NOT re-describe its internals — it records only the
delta and the decisions. See "Delta".

## Decisions (from brainstorming)

- **optimizeimage owns both modes** — offline (mozjpeg/pngquant/oxipng) and online (Tinify
  `--online`). `tinifyimage.sh` keeps no optimization logic of its own.
- **Resize stays in `compresspdf.sh`** — optimizeimage is a pure "optimize this image" primitive
  and knows nothing about `--width`. compresspdf does `mogrify -resize` itself, then calls
  optimizeimage.
- **Only direct vendor deps declared.** optimizeimage carries the
  mozjpeg/pngquant/oxipng/imagemagick/curl/exiftool requirements; compresspdf keeps its direct
  ones (poppler-utils, imagemagick); tinifyimage has no direct vendor tool of its own. The
  dependency on the sibling `optimizeimage` is recorded as a **plain comment**
  `# depends on: optimizeimage.sh`, not a `# requirement:` line.
- **Defer installer tooling.** `installapps`/`requirements.sh` only understand
  `# requirement: vendor/<dep>`; installing sibling scripts is a separate later ticket. For now,
  installing the wrappers also requires installing `optimizeimage.sh` manually — a documented
  limitation.

## Source of truth

`~/pro/kumbukus` repo. New `apps/optimizeimage.sh` → installs to `~/bin`. Modified:
`apps/tinifyimage.sh`, `apps/compresspdf.sh`. No `config.json`/menu changes (the menu calls
`tinifyimage.sh %f`, `tinifyimage.sh %f --no-metadata`, `compresspdf.sh %f`,
`compresspdf.sh %f --width=1000`).

## Component map

```
                    optimizeimage.sh        (offline local + online Tinify; SRC DST)
                   /                \
   tinifyimage.sh (optimized/ wrapper)   compresspdf.sh (pdfimages → resize → optimize → reassemble)
```

## Delta: `optimizeimage.sh` = a copy of `tinifyimage.sh` with these changes

Take `apps/tinifyimage.sh` as a whole (`compress_local`, `compress_online`,
`restore_metadata`, `detect_format`, `require`, `usage`, flag parsing, mode dispatch)
**verbatim**, and apply exactly these changes:

1. **`SRC DST` interface.** Two positional arguments instead of one: input `SRC` and output
   `DST`. The write target becomes `DST` instead of `OPTIMIZED_DIR/basename`.
2. **Drop the `optimized/` logic.** Remove the `OPTIMIZED_DIR`/`OPTIMIZED_FILE` computation and
   the `mkdir -p`. `DST`'s directory must already exist (the caller's job); optimizeimage does
   not create directories. Everywhere the code wrote to `OPTIMIZED_FILE` it now writes to `DST`
   (including `${DST}.work.tmp` for the atomic replace — which gives in-place support when
   `SRC==DST`).
3. **Bugfix** `identify -format '%k %z'` → `'%k %z\n'` (add the newline so `read` doesn't fail
   at EOF).
4. **Drop the dead `--local` alias** (it was a synonym for `--offline`, which is already the
   default; used nowhere).
5. **Remove the two vestigial files in `compress_online`** — `METADATA_FILE` (written via
   `exiftool -j SRC`, then deleted, but never read; the actual restore uses
   `-tagsfromfile SRC`) and `OPTIMIZED_FILE_PROGRESS` (`touch`ed then `rm`ed, never read).
   Delete both their create and remove lines. Verified write-only, so this changes no behavior.
6. **usage** updated for `SRC DST` and without `--local`.
7. **`# requirement:` headers** — keep only the optimization tools:
   `curl, exiftool, mozjpeg, pngquant, oxipng, imagemagick`.

Resulting interface: `optimizeimage.sh [--online|--offline] [--no-metadata] [-q N] [-h|--help]
SRC DST`. Default mode `--offline`.

**Intentional behavior changes are exactly these four — copy everything else verbatim, do NOT
otherwise "tidy":** (3) the `\n` bugfix, (4) dropping `--local`, and (5) removing the two
vestigial files. Every other piece — the full metadata semantics (offline jpeg keeps only
`Orientation` under `--no-metadata`; png keeps nothing; online forces `Orientation=Horizontal`),
the output messages (`(local)`/`(online)` + `-X%`), and the `require()` checks — is carried over
unchanged. Items 1, 2, 6, 7 are interface/packaging mechanics, not optimization-behavior changes.

## `tinifyimage.sh` → thin wrapper

- Keeps the same CLI (minus `--local`): `[--online|--offline] [--no-metadata] [-q N] [-h|--help]
  FILE`. Menu unaffected.
- Computes `DST="$(dirname SRC)/optimized/$(basename SRC)"`, `mkdir -p` the folder, delegates
  forwarding all flags: `optimizeimage <flags> "$SRC" "$DST"`.
- Removes all the moved code (`compress_local`, `compress_online`, `restore_metadata`,
  `detect_format`, `require`).
- Comment `# depends on: optimizeimage.sh`.

## `compresspdf.sh` → drops the inline optimizer

- Removes the `optimize_image()` function.
- In the per-page loop: keep `mogrify -resize "${WIDTH}x>"` when `--width` is given, then call
  `optimizeimage --offline --no-metadata "$img" "$img" >/dev/null` (in-place; metadata is
  meaningless for intermediate page images; stdout suppressed).
- **Untouched:** `--width` parsing, `-*`→exit 1, "No such file"→exit 1, `pdfimages -all`,
  "No images found"→exit 0, `mkdir -p optimized`, `convert "$TEMP_DIR"/img*` reassembly, the
  "Compression finished: <pdf>" message.
- `# requirement:` — only `poppler-utils`, `imagemagick`; comment
  `# depends on: optimizeimage.sh`.

## Behavior preservation (verified against the current scripts)

- **jpg/png PDFs in compresspdf** — identical output (the same mozjpeg/pngquant/oxipng pipeline,
  now via optimizeimage).
- **non-jpg/png PDFs (CCITT/JBIG2/CMYK-as-ppm)** — *the current script already fails*
  empirically: `pdfimages -all` emits a non-jpg/png file (+ a `.params` sidecar), and the final
  `convert` has no decode delegate for CCITT/PARAMS, exiting 1 with no output. The refactor
  reproduces a non-zero exit on the same inputs (optimizeimage exits 1 on the unsupported page
  first). No working behavior is lost. A `--skip-unsupported` flag was considered and
  **rejected**: it would not make such PDFs succeed (downstream `convert` still can't read
  CCITT). Supporting exotic page formats is a separate future improvement, out of scope.

## Error handling

- optimizeimage: SRC exists and is a file; DST given; unknown option → usage + exit 1;
  unsupported type in offline → message + exit 1 (as today).
- Wrappers: if `optimizeimage` is not installed → "command not found" (exit 127). No friendlier
  guard is added (installer support deferred); the limitation is documented here.

## Out of scope (YAGNI / deferred)

- Sibling-dependency support in `installapps`/`requirements.sh` — separate ticket.
- `--width`/resize in optimizeimage.
- Online in-place (`SRC==DST` with `--online`).
- Renaming around the similarly-named `optimizeimagejpegoptim.sh` (left as is).

## Testing

New `tests/behavior/test_optimizeimage.sh` (via `tests/selftest/assert.sh`; needs
imagemagick/mozjpeg/pngquant/oxipng/file):

1. **offline jpeg** → DST smaller than SRC and a valid JPEG.
2. **offline png palette** (≤256 colours, 8-bit) → DST a valid PNG, not larger than SRC.
3. **offline png photo** (>256 colours) → DST a valid PNG (lossless path runs without error).
4. **in-place** (`SRC==DST`) → file optimized in place, still valid.
5. **SRC≠DST** → DST created in an existing directory, SRC untouched.
6. **unsupported type** (`.txt`) in offline → exit 1.
7. **`--no-metadata` on a jpeg** → DST valid, `Orientation` tag kept, other EXIF dropped.

Regression:
- `tests/behavior/test_compresspdf.sh` keeps passing (now via optimizeimage).
- A minimal `test_tinifyimage.sh`: offline on a generated jpeg → a valid `optimized/<name>`
  smaller than the source (wrapper works end-to-end).

Not asserted: non-jpg/png PDFs keep failing in `compresspdf` as they do today (a pre-existing
failure, not a regression). Online (Tinify) paths are not tested automatically (need key +
network).
